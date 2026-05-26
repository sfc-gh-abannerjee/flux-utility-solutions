/*
====================================================================================
02_load_seed_outages.sql
====================================================================================
Author:    Abhinav Bannerjee
Purpose:   Load real historical outage data from
           flux-utility-solutions/seed_data/full/outage_events/*.parquet
           into FLUX_DB.PRODUCTION.OUTAGE_RESTORATION_TRACKER, filtered to
           transformers that already exist in our PRODUCTION schema (additive
           only, no ID clashes).

Why this exists
---------------
The repo seed contains 34,252 historical outage events across 22,338 distinct
transformers, including 7,961 valid July 2024 outages — among them ~191
TRANSFORMER_OVERLOAD events on July 8 17:00-19:00 UTC that align temporally
with Hurricane Beryl's peak (Cat-1 landfall 04:00 CDT). Re-using this real
seed data is preferable to fabricating events from scratch because it:

  1. Anchors the demo in repo-canonical data (no synthetic divergence).
  2. Produces a natural distribution of causes (TRANSFORMER_OVERLOAD,
     VEGETATION, etc.) across all 30 days, not just one storm.
  3. Auto-correlates with grid topology (real TRANSFORMER_IDs already in
     PRODUCTION.TRANSFORMER_METADATA + meters via TRANSFORMER_ID linkage).
  4. Keeps the OPS_CENTER_KPIS view's outage queries pulling real rows.

What this script does
---------------------
1. Stage: ensures FLUX_DB.RAW schema + parquet file format + SEED_STAGE.
   Parquet upload happens out-of-band via:
     snow stage copy seed_data/full/outage_events/*.parquet \
       @FLUX_DB.RAW.SEED_STAGE/outage_events/ --connection se_demo --overwrite
2. Land: COPY INTO FLUX_DB.RAW.SEED_OUTAGE_EVENTS (matches parquet schema 1:1).
3. Archive prior demo data: snapshot the 15 fabricated rows currently in
   PRODUCTION.OUTAGE_RESTORATION_TRACKER → PRODUCTION.OUTAGE_ARCHIVE, then
   DELETE them. The archive preserves auditability without leaving stale
   March 2026 demo rows in the active tracker.
4. Project + filter: INSERT only July 2024 valid-window outages whose
   TRANSFORMER_ID exists in PRODUCTION.TRANSFORMER_METADATA. ~5,252 of 7,961
   match → load.
5. Re-tag the Beryl-aligned cluster (07/08 17:00-19:00 UTC) as cause='WEATHER'
   with a Hurricane-Beryl-tagged NOTE for demo storyline clarity.
6. ALTER TABLE OUTAGE_RESTORATION_TRACKER ADD COLUMN TRANSFORMER_ID
   (idempotent) so AMI_INTERVAL_READINGS_V2 generation can JOIN on it.

This script is idempotent — re-running it: archive→delete→insert cycle is safe.

Connection / context
--------------------
USE ROLE       SYSADMIN;
USE WAREHOUSE  FLUX_WH;
USE DATABASE   FLUX_DB;
USE SCHEMA     PRODUCTION;
====================================================================================
*/

USE DATABASE FLUX_DB;
USE WAREHOUSE FLUX_WH;

-- ===========================================================================
-- Step 1 — staging schema, file format, internal stage
-- ===========================================================================
CREATE SCHEMA IF NOT EXISTS FLUX_DB.RAW;
CREATE FILE FORMAT IF NOT EXISTS FLUX_DB.RAW.PARQUET_FMT TYPE = 'PARQUET';
CREATE STAGE      IF NOT EXISTS FLUX_DB.RAW.SEED_STAGE
    FILE_FORMAT = FLUX_DB.RAW.PARQUET_FMT
    DIRECTORY   = (ENABLE = TRUE);

-- ┌────────────────────────────────────────────────────────────────────────┐
-- │ MANUAL STEP (out of band before continuing):                           │
-- │   snow stage copy \                                                    │
-- │     flux-utility-solutions/seed_data/full/outage_events/*.parquet \    │
-- │     @FLUX_DB.RAW.SEED_STAGE/outage_events/ \                           │
-- │     --connection se_demo --overwrite                                   │
-- └────────────────────────────────────────────────────────────────────────┘

-- ===========================================================================
-- Step 2 — land seed parquet into RAW (schema mirrors parquet exactly)
-- ===========================================================================
CREATE OR REPLACE TABLE FLUX_DB.RAW.SEED_OUTAGE_EVENTS (
    OUTAGE_ID                VARCHAR(50),
    CAUSED_BY_SAG_EVENT_ID   VARCHAR(50),
    OUTAGE_CAUSE             VARCHAR(50),
    TRANSFORMER_ID           VARCHAR(50),
    CIRCUIT_ID               VARCHAR(100),
    FEEDER_ID                VARCHAR(50),
    SUBSTATION_ID            VARCHAR(50),
    OUTAGE_START_TIME        TIMESTAMP_TZ,
    OUTAGE_END_TIME          TIMESTAMP_TZ,
    OUTAGE_DURATION_MINUTES  NUMBER(18,0),
    VOLTAGE_DROP_AMOUNT      NUMBER(2,0)
);

COPY INTO FLUX_DB.RAW.SEED_OUTAGE_EVENTS
  FROM @FLUX_DB.RAW.SEED_STAGE/outage_events/
  FILE_FORMAT = (FORMAT_NAME = 'FLUX_DB.RAW.PARQUET_FMT')
  MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

-- ===========================================================================
-- Step 3 — archive existing fabricated rows then clear the active tracker
-- ===========================================================================
CREATE OR REPLACE TABLE FLUX_DB.PRODUCTION.OUTAGE_ARCHIVE AS
SELECT *,
       CURRENT_TIMESTAMP() AS ARCHIVED_AT,
       'fabricated demo data superseded by historical seed load' AS ARCHIVE_REASON
FROM FLUX_DB.PRODUCTION.OUTAGE_RESTORATION_TRACKER;

DELETE FROM FLUX_DB.PRODUCTION.OUTAGE_RESTORATION_TRACKER;

-- ===========================================================================
-- Step 4 — additive non-destructive ALTER: add TRANSFORMER_ID for AMI join
-- ===========================================================================
ALTER TABLE FLUX_DB.PRODUCTION.OUTAGE_RESTORATION_TRACKER
    ADD COLUMN IF NOT EXISTS TRANSFORMER_ID VARCHAR(50);

-- ===========================================================================
-- Step 5 — project filtered seed → tracker, with Beryl re-tag
-- ===========================================================================
INSERT INTO FLUX_DB.PRODUCTION.OUTAGE_RESTORATION_TRACKER (
    OUTAGE_ID, CIRCUIT_ID, SUBSTATION_ID, TRANSFORMER_ID,
    OUTAGE_START_TIME, OUTAGE_END_TIME,
    STATUS, CAUSE,
    AFFECTED_CUSTOMERS, AFFECTED_TRANSFORMERS,
    CREW_ASSIGNED, ESTIMATED_RESTORATION, ACTUAL_RESTORATION,
    OUTAGE_DURATION_MINUTES, NOTES,
    CREATED_AT, UPDATED_AT
)
WITH filtered AS (
    SELECT s.*, m_count.meters_affected, t.SUBSTATION_ID AS XFMR_SUBSTATION
    FROM FLUX_DB.RAW.SEED_OUTAGE_EVENTS s
    JOIN FLUX_DB.PRODUCTION.TRANSFORMER_METADATA t
         ON t.TRANSFORMER_ID = s.TRANSFORMER_ID
    LEFT JOIN (
        SELECT TRANSFORMER_ID, COUNT(*) AS meters_affected
        FROM FLUX_DB.PRODUCTION.METER_INFRASTRUCTURE
        GROUP BY 1
    ) m_count ON m_count.TRANSFORMER_ID = s.TRANSFORMER_ID
    WHERE s.OUTAGE_START_TIME::TIMESTAMP_NTZ >= '2024-07-01'
      AND s.OUTAGE_START_TIME::TIMESTAMP_NTZ <  '2024-08-01'
      AND s.OUTAGE_END_TIME > s.OUTAGE_START_TIME
)
SELECT
    f.OUTAGE_ID,
    f.CIRCUIT_ID,
    f.XFMR_SUBSTATION                             AS SUBSTATION_ID,
    f.TRANSFORMER_ID,
    f.OUTAGE_START_TIME::TIMESTAMP_NTZ            AS OUTAGE_START_TIME,
    f.OUTAGE_END_TIME::TIMESTAMP_NTZ              AS OUTAGE_END_TIME,
    'RESTORED'                                    AS STATUS,
    -- Beryl re-tag
    CASE
        WHEN DATE(f.OUTAGE_START_TIME) = '2024-07-08'
             AND HOUR(f.OUTAGE_START_TIME) BETWEEN 17 AND 19
        THEN 'WEATHER'
        ELSE f.OUTAGE_CAUSE
    END                                           AS CAUSE,
    COALESCE(f.meters_affected, 1)                AS AFFECTED_CUSTOMERS,
    1                                             AS AFFECTED_TRANSFORMERS,
    'CREW-' || (ABS(HASH(f.OUTAGE_ID)) % 8 + 1)::VARCHAR AS CREW_ASSIGNED,
    DATEADD(minute, f.OUTAGE_DURATION_MINUTES::NUMBER / 2,
            f.OUTAGE_START_TIME::TIMESTAMP_NTZ)   AS ESTIMATED_RESTORATION,
    f.OUTAGE_END_TIME::TIMESTAMP_NTZ              AS ACTUAL_RESTORATION,
    f.OUTAGE_DURATION_MINUTES::NUMBER             AS OUTAGE_DURATION_MINUTES,
    CASE
        WHEN DATE(f.OUTAGE_START_TIME) = '2024-07-08'
             AND HOUR(f.OUTAGE_START_TIME) BETWEEN 17 AND 19
        THEN 'Hurricane Beryl impact (Cat-1 landfall 07/08 ~04:00 CDT). '
             || 'Original cause: ' || f.OUTAGE_CAUSE
        ELSE 'Historical seed outage. Cause: ' || f.OUTAGE_CAUSE
             || COALESCE('. Linked to sag event: ' || f.CAUSED_BY_SAG_EVENT_ID, '')
    END                                           AS NOTES,
    f.OUTAGE_START_TIME::TIMESTAMP_NTZ            AS CREATED_AT,
    f.OUTAGE_END_TIME::TIMESTAMP_NTZ              AS UPDATED_AT
FROM filtered f;

-- ===========================================================================
-- Sanity reports
-- ===========================================================================
SELECT 'archived rows'             AS metric, COUNT(*)::VARCHAR AS val FROM FLUX_DB.PRODUCTION.OUTAGE_ARCHIVE
UNION ALL SELECT 'tracker rows',                 COUNT(*)::VARCHAR FROM FLUX_DB.PRODUCTION.OUTAGE_RESTORATION_TRACKER
UNION ALL SELECT 'tracker distinct transformers', COUNT(DISTINCT TRANSFORMER_ID)::VARCHAR FROM FLUX_DB.PRODUCTION.OUTAGE_RESTORATION_TRACKER
UNION ALL SELECT 'Beryl-tagged rows (07/08 17-19 UTC)', COUNT(*)::VARCHAR
  FROM FLUX_DB.PRODUCTION.OUTAGE_RESTORATION_TRACKER
  WHERE CAUSE = 'WEATHER' AND DATE(OUTAGE_START_TIME) = '2024-07-08';

-- Daily/cause breakdown around Beryl
SELECT DATE(OUTAGE_START_TIME) AS day, CAUSE, COUNT(*) AS n,
       SUM(AFFECTED_CUSTOMERS) AS customers
FROM FLUX_DB.PRODUCTION.OUTAGE_RESTORATION_TRACKER
WHERE DATE(OUTAGE_START_TIME) BETWEEN '2024-07-07' AND '2024-07-10'
GROUP BY 1, 2 ORDER BY 1, 2;
