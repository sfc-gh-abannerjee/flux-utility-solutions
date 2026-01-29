/*
================================================================================
FLUX UTILITY SOLUTIONS - FULL PRODUCTION SEED DATA LOADING SCRIPT
================================================================================
This script loads the complete production seed data from Parquet files.
Data exported from SOURCE_DATABASE.PRODUCTION with ~1.4M total records across 9 tables.

USAGE WITH SNOWFLAKE CLI:
  # Step 1: Upload parquet files to stage
  cd /path/to/flux-utility-solutions
  ./cli/load_seed_data.sh --database FLUX_OPS --warehouse COMPUTE_WH

  # Step 2: Run this script
  snow sql -f scripts/51_load_full_seed_data.sql \
    -D "database='FLUX_OPS'" \
    -D "warehouse='COMPUTE_WH'"

PREREQUISITES:
1. Database and schemas must already exist (run scripts 01-05 first)
2. Parquet files must be uploaded to FULL_SEED_DATA_STAGE

DATA VOLUMES:
- SUBSTATIONS: 275 rows
- CIRCUIT_METADATA: 8,842 rows
- TRANSFORMER_METADATA: 91,554 rows
- METER_INFRASTRUCTURE: 596,906 rows
- CUSTOMERS_MASTER_DATA: 686,359 rows
- WORK_ORDERS: ~25,000 rows
- OUTAGE_EVENTS: ~15,000 rows
- POWER_LINES: ~12,000 rows
- WEATHER_EVENTS: ~500 rows
- AMI_INTERVAL_READINGS: Generated (not loaded from file)
================================================================================
*/

-- Use Jinja2 templating for configuration
USE WAREHOUSE <% warehouse %>;
USE DATABASE <% database %>;
USE SCHEMA PRODUCTION;

-- ============================================================================
-- STEP 1: Create internal stage for full seed data (Parquet format)
-- ============================================================================
CREATE STAGE IF NOT EXISTS FULL_SEED_DATA_STAGE
    FILE_FORMAT = (TYPE = 'PARQUET')
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Internal stage for loading full production seed data from Parquet files';

-- ============================================================================
-- STEP 2: Define file format for Parquet
-- ============================================================================
CREATE OR REPLACE FILE FORMAT PARQUET_FORMAT
    TYPE = 'PARQUET'
    COMPRESSION = 'SNAPPY';

-- ============================================================================
-- STEP 3: Load SUBSTATIONS (275 rows)
-- ============================================================================
SELECT '>>> Loading SUBSTATIONS...' AS status;

TRUNCATE TABLE IF EXISTS SUBSTATIONS;

COPY INTO SUBSTATIONS
FROM (
    SELECT 
        $1:SUBSTATION_ID::VARCHAR,
        $1:SUBSTATION_NAME::VARCHAR,
        $1:LATITUDE::FLOAT,
        $1:LONGITUDE::FLOAT,
        $1:CAPACITY_MVA::FLOAT,
        $1:REGION::VARCHAR,
        $1:VOLTAGE_LEVEL::VARCHAR,
        TRY_TO_DATE($1:COMMISSIONED_DATE::VARCHAR),
        $1:OPERATIONAL_STATUS::VARCHAR,
        $1:SUBSTATION_TYPE::VARCHAR
    FROM @FULL_SEED_DATA_STAGE/substations/
)
FILE_FORMAT = PARQUET_FORMAT
ON_ERROR = 'CONTINUE';

SELECT 'SUBSTATIONS loaded: ' || COUNT(*) || ' rows' AS status FROM SUBSTATIONS;

-- ============================================================================
-- STEP 4: Load CIRCUIT_METADATA (8,842 rows)
-- ============================================================================
SELECT '>>> Loading CIRCUIT_METADATA...' AS status;

TRUNCATE TABLE IF EXISTS CIRCUIT_METADATA;

COPY INTO CIRCUIT_METADATA
FROM (
    SELECT 
        $1:CIRCUIT_ID::VARCHAR,
        $1:SUBSTATION_ID::VARCHAR,
        $1:CIRCUIT_NAME::VARCHAR,
        $1:VOLTAGE_KV::FLOAT,
        $1:LENGTH_MILES::FLOAT,
        $1:CUSTOMER_COUNT::INTEGER,
        $1:PEAK_LOAD_MW::FLOAT,
        $1:CIRCUIT_TYPE::VARCHAR,
        $1:INSTALLATION_YEAR::INTEGER,
        $1:RELIABILITY_INDEX::FLOAT
    FROM @FULL_SEED_DATA_STAGE/circuits/
)
FILE_FORMAT = PARQUET_FORMAT
ON_ERROR = 'CONTINUE';

SELECT 'CIRCUIT_METADATA loaded: ' || COUNT(*) || ' rows' AS status FROM CIRCUIT_METADATA;

-- ============================================================================
-- STEP 5: Load TRANSFORMER_METADATA (91,554 rows)
-- ============================================================================
SELECT '>>> Loading TRANSFORMER_METADATA...' AS status;

TRUNCATE TABLE IF EXISTS TRANSFORMER_METADATA;

COPY INTO TRANSFORMER_METADATA
FROM (
    SELECT 
        $1:TRANSFORMER_ID::VARCHAR,
        $1:SUBSTATION_ID::VARCHAR,
        $1:CIRCUIT_ID::VARCHAR,
        $1:LATITUDE::FLOAT,
        $1:LONGITUDE::FLOAT,
        $1:RATED_KVA::FLOAT,
        $1:INSTALL_YEAR::INTEGER,
        TRY_TO_DATE($1:LAST_MAINTENANCE_DATE::VARCHAR),
        $1:CURRENT_LOAD_KVA::FLOAT,
        $1:PEAK_LOAD_KVA::FLOAT,
        $1:LOAD_UTILIZATION_PCT::FLOAT,
        $1:METER_COUNT::INTEGER,
        $1:HEALTH_SCORE::FLOAT,
        $1:MANUFACTURER::VARCHAR,
        $1:MODEL_NUMBER::VARCHAR
    FROM @FULL_SEED_DATA_STAGE/transformers/
)
FILE_FORMAT = PARQUET_FORMAT
ON_ERROR = 'CONTINUE';

SELECT 'TRANSFORMER_METADATA loaded: ' || COUNT(*) || ' rows' AS status FROM TRANSFORMER_METADATA;

-- ============================================================================
-- STEP 6: Load METER_INFRASTRUCTURE (596,906 rows)
-- ============================================================================
SELECT '>>> Loading METER_INFRASTRUCTURE...' AS status;

TRUNCATE TABLE IF EXISTS METER_INFRASTRUCTURE;

COPY INTO METER_INFRASTRUCTURE
FROM (
    SELECT 
        $1:METER_ID::VARCHAR,
        $1:METER_LATITUDE::FLOAT,
        $1:METER_LONGITUDE::FLOAT,
        $1:METER_TYPE::VARCHAR,
        $1:TRANSFORMER_ID::VARCHAR,
        $1:SUBSTATION_ID::VARCHAR,
        $1:CIRCUIT_ID::VARCHAR,
        $1:HEALTH_SCORE::FLOAT,
        TRY_TO_DATE($1:COMMISSIONED_DATE::VARCHAR),
        $1:CITY::VARCHAR,
        $1:ZIP_CODE::VARCHAR,
        $1:CUSTOMER_SEGMENT_ID::VARCHAR
    FROM @FULL_SEED_DATA_STAGE/meters/
)
FILE_FORMAT = PARQUET_FORMAT
ON_ERROR = 'CONTINUE';

SELECT 'METER_INFRASTRUCTURE loaded: ' || COUNT(*) || ' rows' AS status FROM METER_INFRASTRUCTURE;

-- ============================================================================
-- STEP 7: Load CUSTOMERS_MASTER_DATA (686,359 rows)
-- ============================================================================
SELECT '>>> Loading CUSTOMERS_MASTER_DATA...' AS status;

TRUNCATE TABLE IF EXISTS CUSTOMERS_MASTER_DATA;

COPY INTO CUSTOMERS_MASTER_DATA
FROM (
    SELECT 
        $1:CUSTOMER_ID::VARCHAR,
        $1:FIRST_NAME::VARCHAR,
        $1:LAST_NAME::VARCHAR,
        $1:FULL_NAME::VARCHAR,
        $1:PRIMARY_METER_ID::VARCHAR,
        $1:CUSTOMER_SEGMENT::VARCHAR,
        $1:SERVICE_ADDRESS::VARCHAR,
        $1:SERVICE_COUNTY::VARCHAR,
        $1:CITY::VARCHAR,
        $1:ZIP_CODE::VARCHAR,
        $1:PHONE::VARCHAR,
        $1:EMAIL::VARCHAR,
        $1:ACCOUNT_STATUS::VARCHAR,
        TRY_TO_DATE($1:SERVICE_START_DATE::VARCHAR),
        TRY_TO_TIMESTAMP($1:CREATED_AT::VARCHAR)
    FROM @FULL_SEED_DATA_STAGE/customers/
)
FILE_FORMAT = PARQUET_FORMAT
ON_ERROR = 'CONTINUE';

SELECT 'CUSTOMERS_MASTER_DATA loaded: ' || COUNT(*) || ' rows' AS status FROM CUSTOMERS_MASTER_DATA;

-- ============================================================================
-- STEP 8: Load POWER_LINES (~12,000 rows)
-- ============================================================================
SELECT '>>> Loading POWER_LINES...' AS status;

-- Create table if not exists
CREATE TABLE IF NOT EXISTS POWER_LINES (
    LINE_ID VARCHAR(50) PRIMARY KEY,
    CIRCUIT_ID VARCHAR(50),
    START_LAT FLOAT,
    START_LONG FLOAT,
    END_LAT FLOAT,
    END_LONG FLOAT,
    LENGTH_MILES FLOAT,
    CONDUCTOR_TYPE VARCHAR(50),
    VOLTAGE_KV FLOAT,
    INSTALLATION_YEAR INTEGER,
    CONDITION_RATING VARCHAR(20)
);

TRUNCATE TABLE IF EXISTS POWER_LINES;

COPY INTO POWER_LINES
FROM (
    SELECT 
        $1:LINE_ID::VARCHAR,
        $1:CIRCUIT_ID::VARCHAR,
        $1:START_LAT::FLOAT,
        $1:START_LONG::FLOAT,
        $1:END_LAT::FLOAT,
        $1:END_LONG::FLOAT,
        $1:LENGTH_MILES::FLOAT,
        $1:CONDUCTOR_TYPE::VARCHAR,
        $1:VOLTAGE_KV::FLOAT,
        $1:INSTALLATION_YEAR::INTEGER,
        $1:CONDITION_RATING::VARCHAR
    FROM @FULL_SEED_DATA_STAGE/power_lines/
)
FILE_FORMAT = PARQUET_FORMAT
ON_ERROR = 'CONTINUE';

SELECT 'POWER_LINES loaded: ' || COUNT(*) || ' rows' AS status FROM POWER_LINES;

-- ============================================================================
-- STEP 9: Load WORK_ORDERS (~25,000 rows)
-- ============================================================================
SELECT '>>> Loading WORK_ORDERS...' AS status;

-- Create table if not exists
CREATE TABLE IF NOT EXISTS WORK_ORDERS (
    WORK_ORDER_ID VARCHAR(50) PRIMARY KEY,
    ASSET_TYPE VARCHAR(50),
    ASSET_ID VARCHAR(50),
    WORK_TYPE VARCHAR(50),
    PRIORITY VARCHAR(20),
    STATUS VARCHAR(20),
    SCHEDULED_DATE DATE,
    COMPLETED_DATE DATE,
    ASSIGNED_CREW VARCHAR(100),
    ESTIMATED_HOURS FLOAT,
    ACTUAL_HOURS FLOAT,
    COST_ESTIMATE FLOAT,
    ACTUAL_COST FLOAT,
    DESCRIPTION TEXT,
    CREATED_AT TIMESTAMP_NTZ
);

TRUNCATE TABLE IF EXISTS WORK_ORDERS;

COPY INTO WORK_ORDERS
FROM (
    SELECT 
        $1:WORK_ORDER_ID::VARCHAR,
        $1:ASSET_TYPE::VARCHAR,
        $1:ASSET_ID::VARCHAR,
        $1:WORK_TYPE::VARCHAR,
        $1:PRIORITY::VARCHAR,
        $1:STATUS::VARCHAR,
        TRY_TO_DATE($1:SCHEDULED_DATE::VARCHAR),
        TRY_TO_DATE($1:COMPLETED_DATE::VARCHAR),
        $1:ASSIGNED_CREW::VARCHAR,
        $1:ESTIMATED_HOURS::FLOAT,
        $1:ACTUAL_HOURS::FLOAT,
        $1:COST_ESTIMATE::FLOAT,
        $1:ACTUAL_COST::FLOAT,
        $1:DESCRIPTION::VARCHAR,
        TRY_TO_TIMESTAMP($1:CREATED_AT::VARCHAR)
    FROM @FULL_SEED_DATA_STAGE/work_orders/
)
FILE_FORMAT = PARQUET_FORMAT
ON_ERROR = 'CONTINUE';

SELECT 'WORK_ORDERS loaded: ' || COUNT(*) || ' rows' AS status FROM WORK_ORDERS;

-- ============================================================================
-- STEP 10: Load OUTAGE_EVENTS (~15,000 rows)
-- ============================================================================
SELECT '>>> Loading OUTAGE_EVENTS...' AS status;

-- Create table if not exists
CREATE TABLE IF NOT EXISTS OUTAGE_EVENTS (
    OUTAGE_ID VARCHAR(50) PRIMARY KEY,
    CIRCUIT_ID VARCHAR(50),
    SUBSTATION_ID VARCHAR(50),
    OUTAGE_TYPE VARCHAR(50),
    CAUSE VARCHAR(100),
    START_TIME TIMESTAMP_NTZ,
    END_TIME TIMESTAMP_NTZ,
    DURATION_MINUTES INTEGER,
    CUSTOMERS_AFFECTED INTEGER,
    ESTIMATED_RESTORATION TIMESTAMP_NTZ,
    STATUS VARCHAR(20),
    WEATHER_RELATED BOOLEAN,
    DESCRIPTION TEXT
);

TRUNCATE TABLE IF EXISTS OUTAGE_EVENTS;

COPY INTO OUTAGE_EVENTS
FROM (
    SELECT 
        $1:OUTAGE_ID::VARCHAR,
        $1:CIRCUIT_ID::VARCHAR,
        $1:SUBSTATION_ID::VARCHAR,
        $1:OUTAGE_TYPE::VARCHAR,
        $1:CAUSE::VARCHAR,
        TRY_TO_TIMESTAMP($1:START_TIME::VARCHAR),
        TRY_TO_TIMESTAMP($1:END_TIME::VARCHAR),
        $1:DURATION_MINUTES::INTEGER,
        $1:CUSTOMERS_AFFECTED::INTEGER,
        TRY_TO_TIMESTAMP($1:ESTIMATED_RESTORATION::VARCHAR),
        $1:STATUS::VARCHAR,
        $1:WEATHER_RELATED::BOOLEAN,
        $1:DESCRIPTION::VARCHAR
    FROM @FULL_SEED_DATA_STAGE/outage_events/
)
FILE_FORMAT = PARQUET_FORMAT
ON_ERROR = 'CONTINUE';

SELECT 'OUTAGE_EVENTS loaded: ' || COUNT(*) || ' rows' AS status FROM OUTAGE_EVENTS;

-- ============================================================================
-- STEP 11: Load WEATHER_EVENTS (~500 rows)
-- ============================================================================
SELECT '>>> Loading WEATHER_EVENTS...' AS status;

-- Create table if not exists
CREATE TABLE IF NOT EXISTS WEATHER_EVENTS (
    EVENT_ID VARCHAR(50) PRIMARY KEY,
    EVENT_TYPE VARCHAR(50),
    SEVERITY VARCHAR(20),
    START_TIME TIMESTAMP_NTZ,
    END_TIME TIMESTAMP_NTZ,
    AFFECTED_REGION VARCHAR(100),
    WIND_SPEED_MPH FLOAT,
    PRECIPITATION_INCHES FLOAT,
    TEMPERATURE_F FLOAT,
    DESCRIPTION TEXT
);

TRUNCATE TABLE IF EXISTS WEATHER_EVENTS;

COPY INTO WEATHER_EVENTS
FROM (
    SELECT 
        $1:EVENT_ID::VARCHAR,
        $1:EVENT_TYPE::VARCHAR,
        $1:SEVERITY::VARCHAR,
        TRY_TO_TIMESTAMP($1:START_TIME::VARCHAR),
        TRY_TO_TIMESTAMP($1:END_TIME::VARCHAR),
        $1:AFFECTED_REGION::VARCHAR,
        $1:WIND_SPEED_MPH::FLOAT,
        $1:PRECIPITATION_INCHES::FLOAT,
        $1:TEMPERATURE_F::FLOAT,
        $1:DESCRIPTION::VARCHAR
    FROM @FULL_SEED_DATA_STAGE/weather_events/
)
FILE_FORMAT = PARQUET_FORMAT
ON_ERROR = 'CONTINUE';

SELECT 'WEATHER_EVENTS loaded: ' || COUNT(*) || ' rows' AS status FROM WEATHER_EVENTS;

-- ============================================================================
-- STEP 12: Generate AMI_INTERVAL_READINGS (synthetic time-series data)
-- ============================================================================
SELECT '>>> Generating AMI_INTERVAL_READINGS...' AS status;
SELECT 'Note: Generating 7 days of 15-minute interval data for sampled meters' AS info;

-- Create temporary table for timestamps (7 days * 96 intervals per day = 672 intervals)
CREATE OR REPLACE TEMPORARY TABLE AMI_TIMESTAMPS AS
SELECT 
    DATEADD(MINUTE, seq4() * 15, DATEADD(DAY, -7, CURRENT_TIMESTAMP())) AS reading_time
FROM TABLE(GENERATOR(ROWCOUNT => 672));

-- Clear existing AMI readings
TRUNCATE TABLE IF EXISTS AMI_INTERVAL_READINGS;

-- Generate readings for a sample of meters (to keep size manageable)
-- Use 10,000 meters to generate ~6.7M readings
INSERT INTO AMI_INTERVAL_READINGS (METER_ID, READING_TIMESTAMP, READING_VALUE_KWH, READING_TYPE, QUALITY_FLAG)
SELECT 
    m.METER_ID,
    t.reading_time,
    ROUND(
        CASE 
            -- Base consumption by segment
            WHEN m.CUSTOMER_SEGMENT_ID = 'RESIDENTIAL' THEN 0.5
            WHEN m.CUSTOMER_SEGMENT_ID = 'COMMERCIAL' THEN 1.8
            WHEN m.CUSTOMER_SEGMENT_ID = 'INDUSTRIAL' THEN 5.0
            ELSE 0.8
        END
        -- Time of day pattern
        * CASE 
            WHEN HOUR(t.reading_time) BETWEEN 6 AND 9 THEN 1.3   -- Morning peak
            WHEN HOUR(t.reading_time) BETWEEN 17 AND 21 THEN 1.5 -- Evening peak  
            WHEN HOUR(t.reading_time) BETWEEN 0 AND 5 THEN 0.3   -- Night low
            ELSE 1.0
        END
        -- Day of week pattern
        * CASE 
            WHEN DAYOFWEEK(t.reading_time) IN (0, 6) THEN 0.85 -- Weekend
            ELSE 1.0
        END
        -- Add randomness (20% variance)
        * (0.9 + UNIFORM(0::FLOAT, 0.2::FLOAT, RANDOM()))
    , 3) AS reading_kwh,
    'INTERVAL',
    CASE WHEN UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.98 THEN 'VALID' ELSE 'ESTIMATED' END
FROM (SELECT * FROM METER_INFRASTRUCTURE ORDER BY METER_ID LIMIT 10000) m
CROSS JOIN AMI_TIMESTAMPS t;

SELECT 'AMI_INTERVAL_READINGS generated: ' || COUNT(*) || ' rows' AS status FROM AMI_INTERVAL_READINGS;

-- ============================================================================
-- STEP 13: Final Summary
-- ============================================================================
SELECT '========================================' AS separator;
SELECT '=== FULL SEED DATA LOADING COMPLETE ===' AS message;
SELECT '========================================' AS separator;

SELECT 
    table_name,
    row_count,
    CASE 
        WHEN row_count > 0 THEN 'SUCCESS'
        ELSE 'EMPTY - CHECK STAGE FILES'
    END AS status
FROM (
    SELECT 'SUBSTATIONS' AS table_name, COUNT(*) AS row_count FROM SUBSTATIONS
    UNION ALL SELECT 'CIRCUIT_METADATA', COUNT(*) FROM CIRCUIT_METADATA
    UNION ALL SELECT 'TRANSFORMER_METADATA', COUNT(*) FROM TRANSFORMER_METADATA
    UNION ALL SELECT 'METER_INFRASTRUCTURE', COUNT(*) FROM METER_INFRASTRUCTURE
    UNION ALL SELECT 'CUSTOMERS_MASTER_DATA', COUNT(*) FROM CUSTOMERS_MASTER_DATA
    UNION ALL SELECT 'POWER_LINES', COUNT(*) FROM POWER_LINES
    UNION ALL SELECT 'WORK_ORDERS', COUNT(*) FROM WORK_ORDERS
    UNION ALL SELECT 'OUTAGE_EVENTS', COUNT(*) FROM OUTAGE_EVENTS
    UNION ALL SELECT 'WEATHER_EVENTS', COUNT(*) FROM WEATHER_EVENTS
    UNION ALL SELECT 'AMI_INTERVAL_READINGS', COUNT(*) FROM AMI_INTERVAL_READINGS
)
ORDER BY table_name;
