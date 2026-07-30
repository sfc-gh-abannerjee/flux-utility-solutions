-- =============================================================================
-- 51_generate_ami_sample.sql
-- Generate sample AMI interval readings data
-- =============================================================================
-- Purpose: Create realistic AMI readings when production data isn't available
-- This generates synthetic 15-minute interval readings for all meters
--
-- Jinja2 Variables:
--   <% database %>  - Target database name
--   <% warehouse %> - Target warehouse name
--   <% days %>      - Number of days of data to generate (default: 7)
--
-- Usage:
--   snow sql -f scripts/51_generate_ami_sample.sql -D "database=FLUX_PROD" -D "warehouse=FLUX_WH" -D "days=7"
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE WAREHOUSE IDENTIFIER('<% warehouse %>');
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
    CUSTOMER_SEGMENT_ID,
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
-- Columns: METER_ID, READING_TIMESTAMP, USAGE_KWH, VOLTAGE_V, POWER_FACTOR, CUSTOMER_SEGMENT_ID, SOURCE_TABLE

-- 2026-07-29: renamed TIMESTAMP -> READING_TIMESTAMP and VOLTAGE -> VOLTAGE_V to match
-- the canonical AMI_INTERVAL_READINGS schema that script 06 now creates.
INSERT INTO AMI_INTERVAL_READINGS (
    METER_ID,
    READING_TIMESTAMP,
    USAGE_KWH,
    VOLTAGE_V,
    POWER_FACTOR,
    CUSTOMER_SEGMENT_ID,
    SOURCE_TABLE
)
SELECT
    m.METER_ID,
    t.interval_time AS READING_TIMESTAMP,
    
    -- Usage KWH with realistic patterns
    ROUND(
        m.base_load_kw * 0.25 *  -- 15-minute reading
        CASE 
            WHEN HOUR(t.interval_time) BETWEEN 6 AND 9 THEN 1.5    -- Morning peak
            WHEN HOUR(t.interval_time) BETWEEN 17 AND 21 THEN 1.8  -- Evening peak
            WHEN HOUR(t.interval_time) BETWEEN 0 AND 5 THEN 0.4    -- Night low
            ELSE 1.0
        END *
        (0.8 + (RANDOM() / 10000000000000000000 * 0.4))  -- Random variation
    , 3) AS USAGE_KWH,
    
    -- Voltage (typically 120V with small variation)
    ROUND(120 * (0.95 + (RANDOM() / 10000000000000000000 * 0.1)), 1) AS VOLTAGE_V,
    
    -- Power factor (0.85-0.99)
    ROUND(0.85 + (RANDOM() / 10000000000000000000 * 0.14), 2) AS POWER_FACTOR,
    
    m.CUSTOMER_SEGMENT_ID,
    'GENERATED_SAMPLE' AS SOURCE_TABLE
    
FROM meter_sample m
CROSS JOIN time_spine t;

SELECT 'AMI readings generated: ' || COUNT(*) || ' rows' AS status FROM AMI_INTERVAL_READINGS;

-- =============================================================================
-- Step 4: Summary
-- =============================================================================

SELECT '=== AMI Sample Generation Complete ===' AS phase;

SELECT 
    MIN(READING_TIMESTAMP) AS earliest_reading,
    MAX(READING_TIMESTAMP) AS latest_reading,
    COUNT(DISTINCT METER_ID) AS unique_meters,
    COUNT(*) AS total_readings
FROM AMI_INTERVAL_READINGS;
