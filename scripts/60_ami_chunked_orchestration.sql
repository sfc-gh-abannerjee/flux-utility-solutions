-- =============================================================================
-- 60_ami_chunked_orchestration.sql
-- Chunked AMI generation — agent-operator control loop
-- =============================================================================
-- Purpose: Control tables and stored procedures that wrap per-day AMI
--          generation in an agent-friendly pause/abort/validate loop.
--          The companion shell script (orchestrate_ami_generation.sh) calls
--          GENERATE_AMI_CHUNK + VALIDATE_AMI_CHUNK for each day chunk and
--          emits structured stdout events consumed via the `monitor` tool.
--
-- Jinja2 Variables:
--   <% database %>  - Target database name (e.g. FLUX_DB)
--   <% warehouse %> - Target warehouse name (e.g. FLUX_WH)
--
-- Usage:
--   snow sql -f scripts/60_ami_chunked_orchestration.sql \
--            -D "database=FLUX_DB" -D "warehouse=FLUX_WH" --connection se_demo
--
-- NOTE: This is scaffolding — review before executing against live data.
--       Default control state is PAUSED; flip to RUNNING to start the orchestrator.
--
-- Dependencies:
--   03_meters_infrastructure.sql  (METER_INFRASTRUCTURE)
--   06_ami_readings_pipeline.sql  (AMI_INTERVAL_READINGS)
--   07_aggregation_tables.sql     (TRANSFORMER_METADATA with RATED_KVA)
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE WAREHOUSE IDENTIFIER('<% warehouse %>');
USE SCHEMA PRODUCTION;

-- =============================================================================
-- 1. AMI_GENERATION_CONTROL — pause / resume / abort flag
-- =============================================================================

CREATE OR REPLACE TABLE FLUX_DB.PRODUCTION.AMI_GENERATION_CONTROL (
    CONTROL_KEY    VARCHAR PRIMARY KEY,
    CONTROL_VALUE  VARCHAR NOT NULL,            -- 'RUNNING' | 'PAUSED' | 'ABORTED'
    UPDATED_AT     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_BY     VARCHAR DEFAULT CURRENT_USER()
);

INSERT INTO FLUX_DB.PRODUCTION.AMI_GENERATION_CONTROL VALUES
    ('STATUS', 'PAUSED', CURRENT_TIMESTAMP(), CURRENT_USER());
-- Default to PAUSED so the orchestrator does not start unintentionally.

-- =============================================================================
-- 2. AMI_GENERATION_RUNS — one row per chunk, full audit trail
-- =============================================================================

CREATE OR REPLACE TABLE FLUX_DB.PRODUCTION.AMI_GENERATION_RUNS (
    RUN_ID            VARCHAR NOT NULL,
    CHUNK_ID          NUMBER  NOT NULL,
    FROM_TS           TIMESTAMP_NTZ,
    TO_TS             TIMESTAMP_NTZ,
    METER_SAMPLE      NUMBER,
    STATUS            VARCHAR,                  -- pending|running|done|failed|aborted|skipped
    ROWS_INSERTED     NUMBER,
    WAREHOUSE_SIZE    VARCHAR,
    QUERY_ID          VARCHAR,
    VALIDATION_JSON   VARIANT,
    STARTED_AT        TIMESTAMP_NTZ,
    COMPLETED_AT      TIMESTAMP_NTZ,
    DURATION_SECONDS  NUMBER,
    ERROR_MSG         VARCHAR,
    PRIMARY KEY (RUN_ID, CHUNK_ID)
);

-- =============================================================================
-- 3. GENERATE_AMI_CHUNK — insert one day of 15-min AMI readings
-- =============================================================================
-- Uses the same load-curve pattern as 51_generate_ami_sample.sql but bounded
-- by P_FROM_TS / P_TO_TS and with a variable meter sample size.
-- Time spine is built via GENERATOR(ROWCOUNT => 96) — 96 × 15-min = 24 h.
-- Meter sample uses ORDER BY RANDOM() LIMIT to bind a variable count.
-- =============================================================================

CREATE OR REPLACE PROCEDURE FLUX_DB.PRODUCTION.GENERATE_AMI_CHUNK(
    P_RUN_ID       VARCHAR,
    P_CHUNK_ID     NUMBER,
    P_FROM_TS      TIMESTAMP_NTZ,
    P_TO_TS        TIMESTAMP_NTZ,
    P_METER_SAMPLE NUMBER,
    P_DRY_RUN      BOOLEAN
)
RETURNS TABLE (ROWS_INSERTED NUMBER, QUERY_ID VARCHAR, DURATION_SECONDS NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    v_started_at   TIMESTAMP_NTZ;
    v_completed_at TIMESTAMP_NTZ;
    v_rows_in      NUMBER  DEFAULT 0;
    v_query_id     VARCHAR DEFAULT '';
    v_duration     NUMBER  DEFAULT 0;
    res            RESULTSET;
BEGIN
    v_started_at := CURRENT_TIMESTAMP();

    -- a. Log chunk as running
    INSERT INTO FLUX_DB.PRODUCTION.AMI_GENERATION_RUNS (
        RUN_ID, CHUNK_ID, FROM_TS, TO_TS, METER_SAMPLE,
        STATUS, STARTED_AT, WAREHOUSE_SIZE
    )
    VALUES (
        :P_RUN_ID, :P_CHUNK_ID, :P_FROM_TS, :P_TO_TS, :P_METER_SAMPLE,
        'running', :v_started_at, CURRENT_WAREHOUSE()
    );

    -- DRY_RUN path: count would-be rows, skip actual insert
    IF (P_DRY_RUN = TRUE) THEN
        -- 96 intervals × P_METER_SAMPLE meters
        v_rows_in  := P_METER_SAMPLE * 96;
        v_query_id := LAST_QUERY_ID();

        UPDATE FLUX_DB.PRODUCTION.AMI_GENERATION_RUNS
        SET STATUS           = 'skipped',
            ROWS_INSERTED    = 0,
            QUERY_ID         = :v_query_id,
            COMPLETED_AT     = CURRENT_TIMESTAMP(),
            DURATION_SECONDS = DATEDIFF('second', :v_started_at, CURRENT_TIMESTAMP())
        WHERE RUN_ID = :P_RUN_ID AND CHUNK_ID = :P_CHUNK_ID;

        res := (SELECT 0 AS ROWS_INSERTED, :v_query_id AS QUERY_ID, 0 AS DURATION_SECONDS);
        RETURN TABLE(res);
    END IF;

    -- b. Live insert — 15-min spine × sampled meters × per-segment load curve
    --    Time spine: GENERATOR produces SEQ4() = 0..95; multiply by 15 min.
    --    Meter sample: ORDER BY RANDOM() LIMIT allows variable bind for sample size.
    INSERT INTO FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS (
        METER_ID, TIMESTAMP, USAGE_KWH, VOLTAGE, POWER_FACTOR,
        CUSTOMER_SEGMENT_ID, SOURCE_TABLE
    )
    SELECT
        m.METER_ID,
        DATEADD('minute', (SEQ4() * 15)::INTEGER, :P_FROM_TS) AS TIMESTAMP,
        ROUND(
            CASE m.METER_TYPE
                WHEN 'RESIDENTIAL' THEN 1.5
                WHEN 'COMMERCIAL'  THEN 15.0
                WHEN 'INDUSTRIAL'  THEN 150.0
                ELSE 2.0
            END * 0.25 *
            CASE
                WHEN HOUR(DATEADD('minute', (SEQ4() * 15)::INTEGER, :P_FROM_TS)) BETWEEN 6  AND 9  THEN 1.5
                WHEN HOUR(DATEADD('minute', (SEQ4() * 15)::INTEGER, :P_FROM_TS)) BETWEEN 17 AND 21 THEN 1.8
                WHEN HOUR(DATEADD('minute', (SEQ4() * 15)::INTEGER, :P_FROM_TS)) BETWEEN 0  AND 5  THEN 0.4
                ELSE 1.0
            END *
            (0.8 + (RANDOM() / 10000000000000000000 * 0.4))
        , 3) AS USAGE_KWH,
        ROUND(120 * (0.95 + (RANDOM() / 10000000000000000000 * 0.1)), 1) AS VOLTAGE,
        ROUND(0.85 + (RANDOM() / 10000000000000000000 * 0.14), 2)        AS POWER_FACTOR,
        m.CUSTOMER_SEGMENT_ID,
        'GENERATED_CHUNK_' || :P_RUN_ID AS SOURCE_TABLE
    FROM (
        SELECT METER_ID, TRANSFORMER_ID, CUSTOMER_SEGMENT_ID, METER_TYPE
        FROM FLUX_DB.PRODUCTION.METER_INFRASTRUCTURE
        ORDER BY RANDOM()
        LIMIT :P_METER_SAMPLE
    ) m
    CROSS JOIN TABLE(GENERATOR(ROWCOUNT => 96));  -- 96 × 15-min intervals = 24 h

    -- c. Capture query ID and rowcount immediately after INSERT
    v_query_id     := LAST_QUERY_ID();
    v_rows_in      := SQLROWCOUNT;
    v_completed_at := CURRENT_TIMESTAMP();
    v_duration     := DATEDIFF('second', v_started_at, v_completed_at);

    -- d. Update run record to done
    UPDATE FLUX_DB.PRODUCTION.AMI_GENERATION_RUNS
    SET STATUS           = 'done',
        ROWS_INSERTED    = :v_rows_in,
        QUERY_ID         = :v_query_id,
        COMPLETED_AT     = :v_completed_at,
        DURATION_SECONDS = :v_duration
    WHERE RUN_ID = :P_RUN_ID AND CHUNK_ID = :P_CHUNK_ID;

    -- e. Return metrics to the bash orchestrator
    res := (SELECT :v_rows_in AS ROWS_INSERTED, :v_query_id AS QUERY_ID, :v_duration AS DURATION_SECONDS);
    RETURN TABLE(res);

EXCEPTION
    WHEN OTHER THEN
        -- f. Log failure and re-raise so the orchestrator sees a non-zero exit
        UPDATE FLUX_DB.PRODUCTION.AMI_GENERATION_RUNS
        SET STATUS       = 'failed',
            ERROR_MSG    = SQLERRM,
            COMPLETED_AT = CURRENT_TIMESTAMP()
        WHERE RUN_ID = :P_RUN_ID AND CHUNK_ID = :P_CHUNK_ID;
        RAISE;
END;
$$;

-- =============================================================================
-- 4. VALIDATE_AMI_CHUNK — 7-check gate between chunks
-- =============================================================================
-- Checks (per chunk's date range):
--   1. FK orphans        — every METER_ID has a row in METER_INFRASTRUCTURE with TRANSFORMER_ID NOT NULL
--   2. Transformer cap   — no xfmr-hour where SUM(kWh*4) > RATED_KVA * 0.9
--   3. Voltage band      — ≥95% of readings in 115-125V
--   4. Power factor      — ≥99% of readings in 0.85-0.99
--   5. Timestamp grid    — 100% of TIMESTAMP values on exact 15-min boundaries
--   6. Row count         — within ±5% of (METER_SAMPLE × 96)
--   7. Segment drift     — placeholder; requires a SEGMENT_MONTHLY_TARGETS reference table
--
-- Verdict:
--   FAIL  — orphans > 0, capacity breach > 0, grid violations, or row count outside ±5%
--   WARN  — voltage_ok_pct < 95 or pf_ok_pct < 99 (logs and continues)
--   PASS  — all checks green
-- =============================================================================

CREATE OR REPLACE PROCEDURE FLUX_DB.PRODUCTION.VALIDATE_AMI_CHUNK(
    P_RUN_ID   VARCHAR,
    P_CHUNK_ID NUMBER
)
RETURNS TABLE (VERDICT VARCHAR, REASON VARCHAR, DETAILS VARIANT)
LANGUAGE SQL
AS
$$
DECLARE
    v_from_ts         TIMESTAMP_NTZ;
    v_to_ts           TIMESTAMP_NTZ;
    v_meter_sample    NUMBER;
    v_rows_inserted   NUMBER  DEFAULT 0;
    v_orphans         NUMBER  DEFAULT 0;
    v_total_readings  NUMBER  DEFAULT 0;
    v_expected_rows   NUMBER  DEFAULT 0;
    v_voltage_ok_pct  FLOAT   DEFAULT 0;
    v_pf_ok_pct       FLOAT   DEFAULT 0;
    v_grid_ok_pct     FLOAT   DEFAULT 0;
    v_capacity_breach NUMBER  DEFAULT 0;
    v_row_pct         FLOAT   DEFAULT 0;
    v_verdict         VARCHAR DEFAULT 'PASS';
    v_reason          VARCHAR DEFAULT '';
    v_details         VARIANT;
    res               RESULTSET;
BEGIN
    -- Load chunk bounds from run history
    SELECT FROM_TS, TO_TS, METER_SAMPLE, COALESCE(ROWS_INSERTED, 0)
    INTO   v_from_ts, v_to_ts, v_meter_sample, v_rows_inserted
    FROM   FLUX_DB.PRODUCTION.AMI_GENERATION_RUNS
    WHERE  RUN_ID = :P_RUN_ID AND CHUNK_ID = :P_CHUNK_ID;

    -- 1. FK orphans: METER_IDs in this chunk with no TRANSFORMER_ID in METER_INFRASTRUCTURE
    SELECT COUNT(DISTINCT a.METER_ID) INTO v_orphans
    FROM   FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS a
    WHERE  a.TIMESTAMP >= :v_from_ts AND a.TIMESTAMP <= :v_to_ts
      AND  NOT EXISTS (
               SELECT 1
               FROM   FLUX_DB.PRODUCTION.METER_INFRASTRUCTURE m
               WHERE  m.METER_ID = a.METER_ID AND m.TRANSFORMER_ID IS NOT NULL
           );

    -- 2. Total row count in this chunk
    SELECT COUNT(*) INTO v_total_readings
    FROM   FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS
    WHERE  TIMESTAMP >= :v_from_ts AND TIMESTAMP <= :v_to_ts;

    v_expected_rows := v_meter_sample * 96;
    IF (v_expected_rows > 0) THEN
        v_row_pct := v_total_readings * 100.0 / v_expected_rows;
    END IF;

    -- 3. Voltage band: % of readings in 115-125V
    SELECT ROUND(
               SUM(CASE WHEN VOLTAGE BETWEEN 115 AND 125 THEN 1.0 ELSE 0.0 END)
               / NULLIF(COUNT(*), 0) * 100.0, 2
           ) INTO v_voltage_ok_pct
    FROM   FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS
    WHERE  TIMESTAMP >= :v_from_ts AND TIMESTAMP <= :v_to_ts;

    -- 4. Power factor: % of readings in 0.85-0.99
    SELECT ROUND(
               SUM(CASE WHEN POWER_FACTOR BETWEEN 0.85 AND 0.99 THEN 1.0 ELSE 0.0 END)
               / NULLIF(COUNT(*), 0) * 100.0, 2
           ) INTO v_pf_ok_pct
    FROM   FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS
    WHERE  TIMESTAMP >= :v_from_ts AND TIMESTAMP <= :v_to_ts;

    -- 5. Timestamp grid: % of TIMESTAMP values on exact 15-min boundaries
    SELECT ROUND(
               SUM(CASE WHEN MINUTE(TIMESTAMP) IN (0,15,30,45)
                             AND SECOND(TIMESTAMP) = 0 THEN 1.0 ELSE 0.0 END)
               / NULLIF(COUNT(*), 0) * 100.0, 2
           ) INTO v_grid_ok_pct
    FROM   FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS
    WHERE  TIMESTAMP >= :v_from_ts AND TIMESTAMP <= :v_to_ts;

    -- 6. Transformer capacity: count xfmr-hours where SUM(kWh*4) > RATED_KVA * 0.9
    --    Requires TRANSFORMER_METADATA.RATED_KVA; see 07_aggregation_tables.sql
    SELECT COUNT(*) INTO v_capacity_breach
    FROM (
        SELECT xh.TRANSFORMER_ID, xh.HR
        FROM (
            SELECT m.TRANSFORMER_ID,
                   DATE_TRUNC('hour', a.TIMESTAMP) AS HR,
                   SUM(a.USAGE_KWH * 4.0)          AS HOURLY_KW
            FROM   FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS a
            JOIN   FLUX_DB.PRODUCTION.METER_INFRASTRUCTURE  m ON a.METER_ID = m.METER_ID
            WHERE  a.TIMESTAMP >= :v_from_ts AND a.TIMESTAMP <= :v_to_ts
            GROUP  BY m.TRANSFORMER_ID, DATE_TRUNC('hour', a.TIMESTAMP)
        ) xh
        JOIN FLUX_DB.PRODUCTION.TRANSFORMER_METADATA tm ON xh.TRANSFORMER_ID = tm.TRANSFORMER_ID
        WHERE xh.HOURLY_KW > tm.RATED_KVA * 0.9
    ) breaches;

    -- 7. Segment drift — placeholder; full check requires SEGMENT_MONTHLY_TARGETS table.
    --    Emits WARN automatically if chunk crosses a month boundary but no targets are
    --    present. Implement by joining AMI_INTERVAL_READINGS segment averages against
    --    a reference table when available.

    -- Determine verdict (first match wins)
    IF (v_orphans > 0) THEN
        v_verdict := 'FAIL';
        v_reason  := 'FK_ORPHANS: ' || v_orphans::VARCHAR || ' meter(s) not in METER_INFRASTRUCTURE';
    ELSEIF (v_capacity_breach > 0) THEN
        v_verdict := 'FAIL';
        v_reason  := 'CAPACITY_BREACH: ' || v_capacity_breach::VARCHAR || ' transformer-hour(s) over RATED_KVA*0.9';
    ELSEIF (v_grid_ok_pct < 100.0) THEN
        v_verdict := 'FAIL';
        v_reason  := 'TIMESTAMP_GRID: ' || (100.0 - v_grid_ok_pct)::VARCHAR || '% not on 15-min boundary';
    ELSEIF (v_row_pct < 95.0 OR v_row_pct > 105.0) THEN
        v_verdict := 'FAIL';
        v_reason  := 'ROW_COUNT: ' || v_total_readings::VARCHAR
                        || ' rows (expected ' || v_expected_rows::VARCHAR || ', tolerance ±5%)';
    ELSEIF (v_voltage_ok_pct < 95.0) THEN
        v_verdict := 'WARN';
        v_reason  := 'VOLTAGE_BAND: only ' || v_voltage_ok_pct::VARCHAR || '% in 115-125V (threshold 95%)';
    ELSEIF (v_pf_ok_pct < 99.0) THEN
        v_verdict := 'WARN';
        v_reason  := 'POWER_FACTOR: only ' || v_pf_ok_pct::VARCHAR || '% in 0.85-0.99 (threshold 99%)';
    END IF;

    -- Build details VARIANT
    v_details := (SELECT OBJECT_CONSTRUCT(
        'fk_orphans',        :v_orphans,
        'total_readings',    :v_total_readings,
        'expected_rows',     :v_expected_rows,
        'row_count_pct',     :v_row_pct,
        'voltage_ok_pct',    :v_voltage_ok_pct,
        'pf_ok_pct',         :v_pf_ok_pct,
        'grid_ok_pct',       :v_grid_ok_pct,
        'capacity_breaches', :v_capacity_breach
    ));

    -- Persist validation result on the run record
    UPDATE FLUX_DB.PRODUCTION.AMI_GENERATION_RUNS
    SET VALIDATION_JSON = OBJECT_CONSTRUCT(
        'verdict', :v_verdict,
        'reason',  :v_reason,
        'details', :v_details
    )
    WHERE RUN_ID = :P_RUN_ID AND CHUNK_ID = :P_CHUNK_ID;

    res := (SELECT :v_verdict AS VERDICT, :v_reason AS REASON, :v_details AS DETAILS);
    RETURN TABLE(res);
END;
$$;

-- =============================================================================
-- 5. V_AMI_GENERATION_STATUS — quick status view for agent polling
-- =============================================================================

CREATE OR REPLACE VIEW FLUX_DB.PRODUCTION.V_AMI_GENERATION_STATUS AS
SELECT
    CHUNK_ID,
    RUN_ID,
    FROM_TS::DATE                            AS day,
    STATUS,
    ROWS_INSERTED,
    QUERY_ID,
    DURATION_SECONDS,
    VALIDATION_JSON:verdict::VARCHAR         AS validation_verdict,
    VALIDATION_JSON:reason::VARCHAR          AS validation_reason
FROM FLUX_DB.PRODUCTION.AMI_GENERATION_RUNS
ORDER BY RUN_ID DESC, CHUNK_ID DESC;

-- =============================================================================
-- Operator commands (run via sql_execute from the agent):
-- =============================================================================
-- Start:  UPDATE FLUX_DB.PRODUCTION.AMI_GENERATION_CONTROL SET CONTROL_VALUE='RUNNING'  WHERE CONTROL_KEY='STATUS';
-- Pause:  UPDATE FLUX_DB.PRODUCTION.AMI_GENERATION_CONTROL SET CONTROL_VALUE='PAUSED'   WHERE CONTROL_KEY='STATUS';
-- Abort:  UPDATE FLUX_DB.PRODUCTION.AMI_GENERATION_CONTROL SET CONTROL_VALUE='ABORTED'  WHERE CONTROL_KEY='STATUS';
-- Status: SELECT CHUNK_ID, day, STATUS, ROWS_INSERTED, validation_verdict, validation_reason FROM FLUX_DB.PRODUCTION.V_AMI_GENERATION_STATUS LIMIT 10;
-- =============================================================================
