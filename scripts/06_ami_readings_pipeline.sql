-- =============================================================================
-- 06_ami_readings_pipeline.sql
-- Flux Utility Solutions - AMI Time-Series Tables and Dynamic Tables
-- =============================================================================
-- Purpose: Create AMI interval readings tables with Bronze→Silver→Gold pipeline
-- Dependencies: 04_meters_infrastructure.sql
-- Jinja2 Variables:
--   <% database %>   - Target database name
--   <% warehouse %>  - Warehouse for Dynamic Table refresh
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
    TIMESTAMP TIMESTAMP_NTZ NOT NULL,
    
    -- Measurements
    USAGE_KWH FLOAT,
    VOLTAGE NUMBER(10,0),
    POWER_FACTOR NUMBER(5,2),
    
    -- Context
    CUSTOMER_SEGMENT_ID VARCHAR(20),
    SOURCE_TABLE VARCHAR(50),  -- Data lineage tracking
    
    -- Clustering for query performance
    PRIMARY KEY (METER_ID, TIMESTAMP)
)
CLUSTER BY (DATE_TRUNC('DAY', TIMESTAMP), METER_ID)
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
    TIMESTAMP TIMESTAMP_NTZ,
    USAGE_KWH FLOAT,
    VOLTAGE NUMBER(10,0),
    POWER_FACTOR NUMBER(5,2),
    INGESTION_TIME TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    SOURCE_SYSTEM VARCHAR(50)
)
CLUSTER BY (DATE_TRUNC('HOUR', TIMESTAMP))
COMMENT = 'Near real-time AMI streaming data';

-- -----------------------------------------------------------------------------
-- 4. AMI_READINGS_WITH_VOLTAGE_EVENTS (Silver Layer View)
-- -----------------------------------------------------------------------------
-- Enhanced view adding voltage sag event detection

CREATE OR ALTER VIEW AMI_READINGS_WITH_VOLTAGE_EVENTS AS
SELECT 
    METER_ID,
    TIMESTAMP,
    USAGE_KWH,
    VOLTAGE,
    POWER_FACTOR,
    CUSTOMER_SEGMENT_ID,
    -- Voltage event detection
    CASE 
        WHEN VOLTAGE < 108 THEN 'SEVERE_SAG'
        WHEN VOLTAGE < 114 THEN 'MODERATE_SAG'
        WHEN VOLTAGE > 126 THEN 'SWELL'
        ELSE NULL
    END as SAG_TYPE,
    CASE 
        WHEN VOLTAGE < 114 THEN 120 - VOLTAGE 
        ELSE 0 
    END as VOLTAGE_DROP_AMOUNT,
    CASE 
        WHEN VOLTAGE < 114 THEN 'VSE-' || TO_VARCHAR(TIMESTAMP, 'YYYYMMDDHH24MISS') || '-' || METER_ID
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
    v.TIMESTAMP,
    v.USAGE_KWH,
    v.VOLTAGE,
    v.POWER_FACTOR,
    v.CUSTOMER_SEGMENT_ID,
    v.SAG_TYPE,
    v.VOLTAGE_DROP_AMOUNT,
    v.VOLTAGE_SAG_EVENT_ID,
    -- Outage detection (usage = 0 with low voltage)
    CASE 
        WHEN v.USAGE_KWH = 0 AND v.VOLTAGE < 100 THEN TRUE 
        ELSE FALSE 
    END as IS_OUTAGE,
    -- Adjusted usage (0 during outages)
    CASE 
        WHEN v.USAGE_KWH = 0 AND v.VOLTAGE < 100 THEN 0
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
-- 7. DYNAMIC TABLE: CIRCUIT_STATUS_REALTIME
-- -----------------------------------------------------------------------------
-- Real-time circuit health computed from AMI data

CREATE OR ALTER DYNAMIC TABLE APPLICATIONS.CIRCUIT_STATUS_REALTIME
    TARGET_LAG = '15 minutes'
    WAREHOUSE = <% warehouse %>
AS
SELECT 
    m.CIRCUIT_ID,
    COUNT(DISTINCT a.METER_ID) as ACTIVE_METERS,
    AVG(a.VOLTAGE) as AVG_VOLTAGE,
    AVG(a.USAGE_KWH) as AVG_USAGE_KWH,
    SUM(CASE WHEN a.VOLTAGE < 114 THEN 1 ELSE 0 END) as LOW_VOLTAGE_COUNT,
    SUM(CASE WHEN a.USAGE_KWH = 0 THEN 1 ELSE 0 END) as ZERO_USAGE_COUNT,
    CASE 
        WHEN AVG(a.VOLTAGE) < 114 THEN 'CRITICAL'
        WHEN AVG(a.VOLTAGE) < 118 THEN 'WARNING'
        ELSE 'NORMAL'
    END as CIRCUIT_STATUS,
    MAX(a.TIMESTAMP) as LAST_READING_TIME
FROM PRODUCTION.AMI_INTERVAL_READINGS a
JOIN PRODUCTION.METER_INFRASTRUCTURE m ON a.METER_ID = m.METER_ID
WHERE a.TIMESTAMP > DATEADD('hour', -1, CURRENT_TIMESTAMP())
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
