-- =============================================================================
-- 51_generate_ami_sample.sql
-- Generate sample AMI interval readings data
-- =============================================================================
-- Purpose: Create realistic AMI readings when production data isn't available
-- This generates synthetic 15-minute interval readings for all meters
--
-- Jinja2 Variables:
--   <% database %> - Target database name
--   <% days %> - Number of days of data to generate (default: 7)
--
-- Usage:
--   snow sql -f scripts/51_generate_ami_sample.sql -D "database='FLUX_PROD'" -D "days=7"
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE SCHEMA PRODUCTION;

SET days_to_generate = <% days %>;

SELECT '=== Generating AMI Sample Data ===' AS phase;
SELECT 'Generating ' || $days_to_generate || ' days of 15-minute readings' AS info;

-- =============================================================================
-- Step 1: Create time spine (15-minute intervals)
-- =============================================================================

CREATE OR REPLACE TEMPORARY TABLE time_spine AS
WITH RECURSIVE intervals AS (
    SELECT DATEADD('day', -$days_to_generate, CURRENT_TIMESTAMP())::TIMESTAMP_NTZ AS interval_time
    UNION ALL
    SELECT DATEADD('minute', 15, interval_time)
    FROM intervals
    WHERE interval_time < CURRENT_TIMESTAMP()
)
SELECT interval_time FROM intervals;

SELECT 'Time spine created: ' || COUNT(*) || ' intervals' AS status FROM time_spine;

-- =============================================================================
-- Step 2: Get meter sample (limit for performance)
-- =============================================================================

CREATE OR REPLACE TEMPORARY TABLE meter_sample AS
SELECT 
    METER_ID,
    TRANSFORMER_ID,
    SERVICE_VOLTAGE,
    CASE METER_TYPE
        WHEN 'RESIDENTIAL' THEN 1.5
        WHEN 'COMMERCIAL' THEN 15.0
        WHEN 'INDUSTRIAL' THEN 150.0
        ELSE 2.0
    END AS base_load_kw
FROM METER_INFRASTRUCTURE
SAMPLE (10000 ROWS);  -- Sample 10K meters for reasonable data volume

SELECT 'Meters sampled: ' || COUNT(*) AS status FROM meter_sample;

-- =============================================================================
-- Step 3: Generate AMI readings with realistic patterns
-- =============================================================================

INSERT INTO AMI_INTERVAL_READINGS (
    READING_ID,
    METER_ID,
    TRANSFORMER_ID,
    TIMESTAMP,
    KWH_READING,
    KW_DEMAND,
    VOLTAGE,
    POWER_FACTOR,
    QUALITY_FLAG,
    READ_TYPE
)
SELECT
    -- Generate unique reading ID
    UUID_STRING() AS READING_ID,
    m.METER_ID,
    m.TRANSFORMER_ID,
    t.interval_time AS TIMESTAMP,
    
    -- KWH reading (cumulative, increasing)
    ROUND(
        (ROW_NUMBER() OVER (PARTITION BY m.METER_ID ORDER BY t.interval_time) * 0.25 * m.base_load_kw) +
        -- Add seasonal variation
        (m.base_load_kw * 0.3 * SIN(2 * PI() * DAYOFYEAR(t.interval_time) / 365)) +
        -- Add daily pattern (peaks at 7am and 7pm)
        (m.base_load_kw * 0.5 * (
            CASE 
                WHEN HOUR(t.interval_time) BETWEEN 6 AND 9 THEN 1.5
                WHEN HOUR(t.interval_time) BETWEEN 17 AND 21 THEN 1.8
                WHEN HOUR(t.interval_time) BETWEEN 0 AND 5 THEN 0.4
                ELSE 1.0
            END
        )) +
        -- Random variation
        (RANDOM() / 10000000000000000000 * m.base_load_kw * 0.2)
    , 3) AS KWH_READING,
    
    -- KW demand (instantaneous)
    ROUND(
        m.base_load_kw * 
        CASE 
            WHEN HOUR(t.interval_time) BETWEEN 6 AND 9 THEN 1.5
            WHEN HOUR(t.interval_time) BETWEEN 17 AND 21 THEN 1.8
            WHEN HOUR(t.interval_time) BETWEEN 0 AND 5 THEN 0.4
            ELSE 1.0
        END *
        (0.8 + (RANDOM() / 10000000000000000000 * 0.4))
    , 2) AS KW_DEMAND,
    
    -- Voltage (typically 120V or 240V with small variation)
    ROUND(
        m.SERVICE_VOLTAGE * (0.95 + (RANDOM() / 10000000000000000000 * 0.1))
    , 1) AS VOLTAGE,
    
    -- Power factor (0.85-0.99)
    ROUND(0.85 + (RANDOM() / 10000000000000000000 * 0.14), 2) AS POWER_FACTOR,
    
    -- Quality flag (mostly good, occasional estimates)
    CASE 
        WHEN RANDOM() / 10000000000000000000 < 0.02 THEN 'ESTIMATED'
        WHEN RANDOM() / 10000000000000000000 < 0.005 THEN 'SUSPECT'
        ELSE 'ACTUAL'
    END AS QUALITY_FLAG,
    
    'SCHEDULED' AS READ_TYPE
    
FROM meter_sample m
CROSS JOIN time_spine t;

SELECT 'AMI readings generated: ' || COUNT(*) || ' rows' AS status FROM AMI_INTERVAL_READINGS;

-- =============================================================================
-- Step 4: Generate aggregated data
-- =============================================================================

-- Transformer hourly load aggregation
INSERT INTO TRANSFORMER_HOURLY_LOAD (
    TRANSFORMER_ID,
    HOUR_TIMESTAMP,
    TOTAL_KWH,
    PEAK_KW,
    AVG_KW,
    METER_COUNT,
    AVG_VOLTAGE,
    MIN_VOLTAGE,
    MAX_VOLTAGE,
    LOAD_FACTOR
)
SELECT 
    TRANSFORMER_ID,
    DATE_TRUNC('HOUR', TIMESTAMP) AS HOUR_TIMESTAMP,
    SUM(KWH_READING) AS TOTAL_KWH,
    MAX(KW_DEMAND) AS PEAK_KW,
    AVG(KW_DEMAND) AS AVG_KW,
    COUNT(DISTINCT METER_ID) AS METER_COUNT,
    AVG(VOLTAGE) AS AVG_VOLTAGE,
    MIN(VOLTAGE) AS MIN_VOLTAGE,
    MAX(VOLTAGE) AS MAX_VOLTAGE,
    AVG(KW_DEMAND) / NULLIF(MAX(KW_DEMAND), 0) AS LOAD_FACTOR
FROM AMI_INTERVAL_READINGS
GROUP BY TRANSFORMER_ID, DATE_TRUNC('HOUR', TIMESTAMP);

SELECT 'Transformer hourly load: ' || COUNT(*) || ' rows' AS status FROM TRANSFORMER_HOURLY_LOAD;

-- =============================================================================
-- Summary
-- =============================================================================

SELECT '=== AMI Data Generation Complete ===' AS phase;

SELECT 
    'AMI_INTERVAL_READINGS' AS table_name, COUNT(*) AS rows FROM AMI_INTERVAL_READINGS
UNION ALL
SELECT 'TRANSFORMER_HOURLY_LOAD', COUNT(*) FROM TRANSFORMER_HOURLY_LOAD
ORDER BY table_name;
