-- =============================================================================
-- 06_ami_readings_pipeline.sql
-- Flux Utility Solutions - AMI Time-Series Tables and Dynamic Tables
-- =============================================================================
-- Purpose: Create AMI interval readings tables with Bronze→Silver→Gold pipeline
-- Dependencies: 04_meters_infrastructure.sql
-- Jinja2 Variables:
--   <% database %>   - Target database name
--   <% warehouse %>  - Warehouse for Dynamic Table refresh
--
-- NOTE (2026-05-26): DATA POPULATION — Realistic AMI Variance Pipeline
-- -----------------------------------------------------------------------
-- This script creates the table/view DDL only. The flat GENERATE_AMI_BATCH
-- procedure (originally in AMI_MIGRATION_DDL.sql) has been replaced with a
-- realistic one-shot generator. To populate AMI_INTERVAL_READINGS with
-- physically-accurate data, run the scripts in order:
--   scripts/realistic_data/01_meter_persistence_seed.sql   — METER_PERSONA_PARAMS
--   scripts/realistic_data/02_load_seed_outages.sql        — outage events
--   scripts/realistic_data/03_generate_ami_realistic.sql   — 288M-row generator
--   scripts/realistic_data/04_rebuild_transformer_hourly_load.sql
--   scripts/realistic_data/05_swap_and_finalize.sql
--   scripts/realistic_data/99_validation.sql               — 15-check validation
-- The new generator features: segment baselines + per-class diurnal curves
-- (RES/COM/IND/GOV), real Houston weather correlation, Hurricane Beryl outage
-- zeros, EV/pool/solar special loads, per-meter persistent personas, and
-- lognormal noise for right-skewed residuals.
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE WAREHOUSE IDENTIFIER('<% warehouse %>');
USE SCHEMA PRODUCTION;

-- -----------------------------------------------------------------------------
-- 1. AMI_INTERVAL_READINGS (Gold Layer - Main Table)
-- -----------------------------------------------------------------------------
-- 7.1 BILLION rows of 15-minute interval AMI data
-- Time range: July 2024 - August 2025 (summer focus)

CREATE OR ALTER TABLE AMI_INTERVAL_READINGS (
    -- Keys
    METER_ID VARCHAR(20) NOT NULL,
    READING_TIMESTAMP TIMESTAMP_NTZ NOT NULL,
    
    -- Measurements
    USAGE_KWH FLOAT,
    VOLTAGE_V NUMBER(10,0),
    POWER_FACTOR NUMBER(5,2),
    
    -- Context
    CUSTOMER_SEGMENT_ID VARCHAR(20),
    SOURCE_TABLE VARCHAR(50),  -- Data lineage tracking
    
    -- Clustering for query performance
    PRIMARY KEY (METER_ID, READING_TIMESTAMP)
)
CLUSTER BY (DATE_TRUNC('DAY', READING_TIMESTAMP), METER_ID)
COMMENT = 'AMI interval readings - 7.1B rows, 15-minute granularity, Jul 2024 - Aug 2025';

-- -----------------------------------------------------------------------------
-- 2. AMI_RAW_JSON (Bronze Layer)
-- -----------------------------------------------------------------------------
-- Raw JSON ingestion for streaming AMI data

CREATE OR ALTER TABLE AMI_RAW_JSON (
    RAW_ID NUMBER(18,0) AUTOINCREMENT PRIMARY KEY,
    INGESTION_TIME TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    SOURCE_SYSTEM VARCHAR(50),
    RAW_PAYLOAD VARIANT,
    PROCESSED_FLAG BOOLEAN DEFAULT FALSE,
    PROCESSED_AT TIMESTAMP_NTZ
)
COMMENT = 'Bronze layer - raw JSON AMI data ingestion';

-- -----------------------------------------------------------------------------
-- 3. AMI_STREAMING_DATA (Near Real-Time)
-- -----------------------------------------------------------------------------
-- Recent streaming data before aggregation

CREATE OR ALTER TABLE AMI_STREAMING_DATA (
    METER_ID VARCHAR(20),
    READING_TIMESTAMP TIMESTAMP_NTZ,
    USAGE_KWH FLOAT,
    VOLTAGE_V NUMBER(10,0),
    POWER_FACTOR NUMBER(5,2),
    INGESTION_TIME TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    SOURCE_SYSTEM VARCHAR(50)
)
CLUSTER BY (DATE_TRUNC('HOUR', READING_TIMESTAMP))
COMMENT = 'Near real-time AMI streaming data';

-- -----------------------------------------------------------------------------
-- 4. AMI_READINGS_WITH_VOLTAGE_EVENTS (Silver Layer View)
-- -----------------------------------------------------------------------------
-- Enhanced view adding voltage sag event detection

CREATE OR ALTER VIEW AMI_READINGS_WITH_VOLTAGE_EVENTS AS
SELECT 
    METER_ID,
    READING_TIMESTAMP,
    USAGE_KWH,
    VOLTAGE_V,
    POWER_FACTOR,
    CUSTOMER_SEGMENT_ID,
    -- Voltage event detection
    CASE 
        WHEN VOLTAGE_V < 108 THEN 'SEVERE_SAG'
        WHEN VOLTAGE_V < 114 THEN 'MODERATE_SAG'
        WHEN VOLTAGE_V > 126 THEN 'SWELL'
        ELSE NULL
    END as SAG_TYPE,
    CASE 
        WHEN VOLTAGE_V < 114 THEN 120 - VOLTAGE_V 
        ELSE 0 
    END as VOLTAGE_DROP_AMOUNT,
    CASE 
        WHEN VOLTAGE_V < 114 THEN 'VSE-' || TO_VARCHAR(READING_TIMESTAMP, 'YYYYMMDDHH24MISS') || '-' || METER_ID
        ELSE NULL
    END as VOLTAGE_SAG_EVENT_ID
FROM AMI_INTERVAL_READINGS;

-- -----------------------------------------------------------------------------
-- 5. AMI_READINGS_FINAL (Gold Layer View with Outage Tracking)
-- -----------------------------------------------------------------------------
-- Final enhanced view with outage correlation

CREATE OR ALTER VIEW AMI_READINGS_FINAL AS
SELECT 
    v.METER_ID,
    v.READING_TIMESTAMP,
    v.USAGE_KWH,
    v.VOLTAGE_V,
    v.POWER_FACTOR,
    v.CUSTOMER_SEGMENT_ID,
    v.SAG_TYPE,
    v.VOLTAGE_DROP_AMOUNT,
    v.VOLTAGE_SAG_EVENT_ID,
    -- Outage detection (usage = 0 with low voltage)
    CASE 
        WHEN v.USAGE_KWH = 0 AND v.VOLTAGE_V < 100 THEN TRUE 
        ELSE FALSE 
    END as IS_OUTAGE,
    -- Adjusted usage (0 during outages)
    CASE 
        WHEN v.USAGE_KWH = 0 AND v.VOLTAGE_V < 100 THEN 0
        ELSE v.USAGE_KWH 
    END as USAGE_KWH_ADJUSTED
FROM AMI_READINGS_WITH_VOLTAGE_EVENTS v;

-- -----------------------------------------------------------------------------
-- 6. AMI_MONTHLY_USAGE (Aggregated Gold Layer)
-- -----------------------------------------------------------------------------
-- Pre-aggregated monthly totals for dashboard queries

CREATE OR ALTER TABLE AMI_MONTHLY_USAGE (
    METER_ID VARCHAR(20) NOT NULL,
    USAGE_MONTH DATE NOT NULL,  -- First of month
    
    -- Aggregations
    TOTAL_KWH NUMBER(15,2),
    AVG_DAILY_KWH NUMBER(10,2),
    PEAK_KWH NUMBER(10,2),
    MIN_KWH NUMBER(10,2),
    READING_COUNT NUMBER(10,0),
    
    -- Computed metrics
    AVG_VOLTAGE NUMBER(10,2),
    LOW_VOLTAGE_READINGS NUMBER(10,0),
    OUTAGE_INTERVALS NUMBER(10,0),
    
    -- YoY comparison
    PRIOR_YEAR_KWH NUMBER(15,2),
    YOY_CHANGE_PCT NUMBER(5,2),
    
    PRIMARY KEY (METER_ID, USAGE_MONTH)
)
CLUSTER BY (USAGE_MONTH, METER_ID)
COMMENT = 'Monthly AMI aggregations - 2.4M rows for dashboard performance';

-- -----------------------------------------------------------------------------
-- 7. DYNAMIC TABLE: CIRCUIT_HEALTH_REALTIME
-- -----------------------------------------------------------------------------
-- Real-time circuit health computed from AMI data

-- 2026-07-29: two fixes, both of which had been applied to the live account in an
-- earlier session but never propagated back here -- so redeploying this script
-- silently reintroduced the broken version.
--
-- 1. TARGET_LAG was '15 minutes'. The AMI source is a static historical load, so a
--    15-minute lag rescanned 288,000,000 rows for no new data. Raised to 24 hours.
-- 2. The window was  READING_TIMESTAMP > DATEADD('hour', -1, CURRENT_TIMESTAMP()).
--    The AMI series ENDS 2024-07-30, so "the last hour" is ~729 days in the future and
--    the table was EMPTY BY CONSTRUCTION -- it sat at 0 rows for months and nobody
--    noticed, because an empty dynamic table looks identical to a quiet grid. The
--    window is now anchored to the data's own maximum timestamp.
--
-- NOTE: the MAX() scalar subquery forces FULL refresh mode -- Snowflake reports
-- "Change tracking is not supported on queries with subquery expressions." That is an
-- acceptable trade for correctness here, since the source does not change.
CREATE OR ALTER DYNAMIC TABLE APPLICATIONS.CIRCUIT_HEALTH_REALTIME
    TARGET_LAG = '24 hours'
    WAREHOUSE = <% warehouse %>
AS
SELECT 
    m.CIRCUIT_ID,
    COUNT(DISTINCT a.METER_ID) as ACTIVE_METERS,
    AVG(a.VOLTAGE_V) as AVG_VOLTAGE_V,
    AVG(a.USAGE_KWH) as AVG_USAGE_KWH,
    SUM(CASE WHEN a.VOLTAGE_V < 114 THEN 1 ELSE 0 END) as LOW_VOLTAGE_COUNT,
    SUM(CASE WHEN a.USAGE_KWH = 0 THEN 1 ELSE 0 END) as ZERO_USAGE_COUNT,
    CASE 
        WHEN AVG(a.VOLTAGE_V) < 114 THEN 'CRITICAL'
        WHEN AVG(a.VOLTAGE_V) < 118 THEN 'WARNING'
        ELSE 'NORMAL'
    END as HEALTH_STATUS,
    MAX(a.READING_TIMESTAMP) as LAST_READING_TIME
FROM PRODUCTION.AMI_INTERVAL_READINGS a
JOIN PRODUCTION.METER_INFRASTRUCTURE m ON a.METER_ID = m.METER_ID
WHERE a.READING_TIMESTAMP > DATEADD(
        'hour', -1,
        (SELECT MAX(READING_TIMESTAMP) FROM PRODUCTION.AMI_INTERVAL_READINGS)
      )
GROUP BY m.CIRCUIT_ID;

-- -----------------------------------------------------------------------------
-- 8. VERIFICATION
-- -----------------------------------------------------------------------------

SELECT 'AMI_INTERVAL_READINGS' as table_name, COUNT(*) as row_count FROM AMI_INTERVAL_READINGS
UNION ALL
SELECT 'AMI_MONTHLY_USAGE', COUNT(*) FROM AMI_MONTHLY_USAGE
UNION ALL
SELECT 'AMI_RAW_JSON', COUNT(*) FROM AMI_RAW_JSON;

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 07_aggregation_tables.sql to create transformer load tables
-- =============================================================================
