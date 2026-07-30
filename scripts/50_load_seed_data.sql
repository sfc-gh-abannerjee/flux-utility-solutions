/*
================================================================================
FLUX UTILITY SOLUTIONS - SEED DATA LOADING SCRIPT
================================================================================
This script loads seed data from bundled CSV files into the core tables.
The CSV files are located in seed_data/csv/ directory of the repository.

USAGE WITH SNOWFLAKE CLI:
  snow sql -f scripts/50_load_seed_data.sql \
    -D "database='FLUX_OPS'" \
    -D "warehouse='COMPUTE_WH'"

PREREQUISITES:
1. Database and schemas must already exist (run scripts 01-04 first)
2. CSV files must be available locally from the repository
================================================================================
*/

-- Use Jinja2 templating for configuration
USE WAREHOUSE <% warehouse %>;
USE DATABASE <% database %>;
USE SCHEMA PRODUCTION;

-- ============================================================================
-- STEP 1: Create internal stage for seed data
-- ============================================================================
CREATE STAGE IF NOT EXISTS SEED_DATA_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Internal stage for loading seed data from repository CSV files';

-- ============================================================================
-- STEP 2: Define file formats
-- ============================================================================
CREATE OR REPLACE FILE FORMAT CSV_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL', 'None')
    EMPTY_FIELD_AS_NULL = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;

-- ============================================================================
-- STEP 3: Instructions for uploading files
-- ============================================================================
/*
IMPORTANT: Before running the COPY INTO statements below, you must PUT the 
CSV files to the stage. Run these commands from your terminal:

# Navigate to repository root
cd /path/to/flux-utility-solutions

# Upload seed data files using Snowflake CLI
snow stage copy seed_data/csv/substations.csv @<% database %>.PRODUCTION.SEED_DATA_STAGE/substations/ --overwrite
snow stage copy seed_data/csv/transformers.csv @<% database %>.PRODUCTION.SEED_DATA_STAGE/transformers/ --overwrite
snow stage copy seed_data/csv/meters.csv @<% database %>.PRODUCTION.SEED_DATA_STAGE/meters/ --overwrite
snow stage copy seed_data/csv/customers.csv @<% database %>.PRODUCTION.SEED_DATA_STAGE/customers/ --overwrite

OR using SQL PUT command (from SnowSQL):
PUT file://seed_data/csv/substations.csv @SEED_DATA_STAGE/substations/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://seed_data/csv/transformers.csv @SEED_DATA_STAGE/transformers/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://seed_data/csv/meters.csv @SEED_DATA_STAGE/meters/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://seed_data/csv/customers.csv @SEED_DATA_STAGE/customers/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
*/

-- ============================================================================
-- STEP 4: Load SUBSTATIONS data
-- ============================================================================
TRUNCATE TABLE IF EXISTS SUBSTATIONS;

COPY INTO SUBSTATIONS (
    SUBSTATION_ID,
    SUBSTATION_NAME,
    LATITUDE,
    LONGITUDE,
    CAPACITY_MVA,
    REGION,
    VOLTAGE_LEVEL,
    COMMISSIONED_DATE,
    OPERATIONAL_STATUS,
    SUBSTATION_TYPE
)
FROM (
    SELECT 
        $1,  -- SUBSTATION_ID
        $2,  -- SUBSTATION_NAME
        $3,  -- LATITUDE
        $4,  -- LONGITUDE
        $5,  -- CAPACITY_MVA
        $6,  -- REGION
        $7,  -- VOLTAGE_LEVEL
        TRY_TO_DATE($8, 'YYYY-MM-DD'),  -- COMMISSIONED_DATE
        $9,  -- OPERATIONAL_STATUS
        $10  -- SUBSTATION_TYPE
    FROM @SEED_DATA_STAGE/substations/
)
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'CONTINUE';

SELECT 'SUBSTATIONS loaded: ' || COUNT(*) || ' rows' AS status FROM SUBSTATIONS;

-- ============================================================================
-- STEP 5: Load TRANSFORMER_METADATA data
-- ============================================================================
TRUNCATE TABLE IF EXISTS TRANSFORMER_METADATA;

COPY INTO TRANSFORMER_METADATA (
    TRANSFORMER_ID,
    SUBSTATION_ID,
    CIRCUIT_ID,
    LATITUDE,
    LONGITUDE,
    RATED_KVA,
    INSTALL_YEAR,
    LAST_MAINTENANCE_DATE,
    CURRENT_LOAD_KVA,
    PEAK_LOAD_KVA,
    LOAD_UTILIZATION_PCT,
    METER_COUNT,
    HEALTH_SCORE,
    MANUFACTURER,
    MODEL_NUMBER
)
FROM (
    SELECT 
        $1,   -- TRANSFORMER_ID
        $2,   -- SUBSTATION_ID
        $3,   -- CIRCUIT_ID
        $4,   -- LATITUDE
        $5,   -- LONGITUDE
        $6,   -- RATED_KVA
        $7,   -- INSTALL_YEAR
        TRY_TO_DATE($8, 'YYYY-MM-DD'),  -- LAST_MAINTENANCE_DATE
        $9,   -- CURRENT_LOAD_KVA
        $10,  -- PEAK_LOAD_KVA
        $11,  -- LOAD_UTILIZATION_PCT
        $12,  -- METER_COUNT
        $13,  -- HEALTH_SCORE
        $14,  -- MANUFACTURER
        $15   -- MODEL_NUMBER
    FROM @SEED_DATA_STAGE/transformers/
)
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'CONTINUE';

SELECT 'TRANSFORMER_METADATA loaded: ' || COUNT(*) || ' rows' AS status FROM TRANSFORMER_METADATA;

-- ============================================================================
-- STEP 6: Load METER_INFRASTRUCTURE data
-- ============================================================================
TRUNCATE TABLE IF EXISTS METER_INFRASTRUCTURE;

COPY INTO METER_INFRASTRUCTURE (
    METER_ID,
    METER_LATITUDE,
    METER_LONGITUDE,
    METER_TYPE,
    TRANSFORMER_ID,
    SUBSTATION_ID,
    CIRCUIT_ID,
    HEALTH_SCORE,
    COMMISSIONED_DATE,
    CITY,
    ZIP_CODE,
    CUSTOMER_SEGMENT_ID
)
FROM (
    SELECT 
        $1,   -- METER_ID
        $2,   -- METER_LATITUDE
        $3,   -- METER_LONGITUDE
        $4,   -- METER_TYPE
        $5,   -- TRANSFORMER_ID
        $6,   -- SUBSTATION_ID
        $7,   -- CIRCUIT_ID
        $8,   -- HEALTH_SCORE
        TRY_TO_DATE($9, 'YYYY-MM-DD'),  -- COMMISSIONED_DATE
        $10,  -- CITY
        $11,  -- ZIP_CODE
        $12   -- CUSTOMER_SEGMENT_ID
    FROM @SEED_DATA_STAGE/meters/
)
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'CONTINUE';

SELECT 'METER_INFRASTRUCTURE loaded: ' || COUNT(*) || ' rows' AS status FROM METER_INFRASTRUCTURE;

-- ============================================================================
-- STEP 7: Load CUSTOMERS_MASTER_DATA
-- ============================================================================
TRUNCATE TABLE IF EXISTS CUSTOMERS_MASTER_DATA;

COPY INTO CUSTOMERS_MASTER_DATA (
    CUSTOMER_ID,
    FIRST_NAME,
    LAST_NAME,
    FULL_NAME,
    PRIMARY_METER_ID,
    CUSTOMER_SEGMENT,
    SERVICE_ADDRESS,
    SERVICE_COUNTY,
    CITY,
    ZIP_CODE,
    PHONE,
    EMAIL,
    ACCOUNT_STATUS,
    SERVICE_START_DATE
)
FROM (
    SELECT 
        $1,   -- CUSTOMER_ID
        $2,   -- FIRST_NAME
        $3,   -- LAST_NAME
        $4,   -- FULL_NAME
        $5,   -- PRIMARY_METER_ID
        $6,   -- CUSTOMER_SEGMENT
        $7,   -- SERVICE_ADDRESS
        $8,   -- SERVICE_COUNTY
        $9,   -- CITY
        $10,  -- ZIP_CODE
        $11,  -- PHONE
        $12,  -- EMAIL
        $13,  -- ACCOUNT_STATUS
        TRY_TO_DATE($14, 'YYYY-MM-DD')  -- SERVICE_START_DATE
    FROM @SEED_DATA_STAGE/customers/
)
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'CONTINUE';

SELECT 'CUSTOMERS_MASTER_DATA loaded: ' || COUNT(*) || ' rows' AS status FROM CUSTOMERS_MASTER_DATA;

-- ============================================================================
-- STEP 8: Generate AMI readings for loaded meters (synthetic time-series)
-- ============================================================================
-- This generates realistic AMI meter readings for the past 7 days
-- based on the meters loaded from seed data

CREATE OR REPLACE TEMPORARY TABLE AMI_TIMESTAMPS AS
SELECT 
    DATEADD(HOUR, seq4(), DATEADD(DAY, -7, CURRENT_TIMESTAMP())) AS reading_time
FROM TABLE(GENERATOR(ROWCOUNT => 168));  -- 7 days * 24 hours

-- Insert AMI readings
-- 2026-07-29: column list was (METER_ID, TIMESTAMP, USAGE_KWH, VOLTAGE, ...), which no
-- longer matches AMI_INTERVAL_READINGS. Script 06 now creates the canonical live schema
-- (READING_TIMESTAMP, VOLTAGE_V), so this INSERT failed with "invalid identifier
-- 'TIMESTAMP'". Only the AMI columns are renamed here -- HOUSTON_WEATHER_HOURLY and the
-- other seed tables keep their own timestamp column names.
INSERT INTO AMI_INTERVAL_READINGS (METER_ID, READING_TIMESTAMP, USAGE_KWH, VOLTAGE_V, POWER_FACTOR, CUSTOMER_SEGMENT_ID, SOURCE_TABLE)
SELECT 
    m.METER_ID,
    t.reading_time,
    ROUND(
        CASE 
            -- Base consumption by segment
            WHEN m.CUSTOMER_SEGMENT_ID = 'RESIDENTIAL' THEN 0.8
            WHEN m.CUSTOMER_SEGMENT_ID = 'COMMERCIAL' THEN 2.5
            WHEN m.CUSTOMER_SEGMENT_ID = 'INDUSTRIAL' THEN 8.0
            ELSE 1.0
        END
        -- Time of day pattern
        * CASE 
            WHEN HOUR(t.reading_time) BETWEEN 6 AND 9 THEN 1.3   -- Morning peak
            WHEN HOUR(t.reading_time) BETWEEN 17 AND 21 THEN 1.5 -- Evening peak
            WHEN HOUR(t.reading_time) BETWEEN 0 AND 5 THEN 0.4   -- Night low
            ELSE 1.0
        END
        -- Add randomness (0.8 to 1.2 multiplier)
        * (0.8 + UNIFORM(0::FLOAT, 0.4::FLOAT, RANDOM()))
    , 3) AS usage_kwh,
    120 + ROUND(UNIFORM(0::FLOAT, 5::FLOAT, RANDOM()), 1) AS voltage,  -- ~120V with slight variation
    0.85 + ROUND(UNIFORM(0::FLOAT, 0.15::FLOAT, RANDOM()), 2) AS power_factor,  -- 0.85-1.0 range
    m.CUSTOMER_SEGMENT_ID,
    'SEED_DATA'
FROM METER_INFRASTRUCTURE m
CROSS JOIN AMI_TIMESTAMPS t
WHERE m.METER_ID IS NOT NULL;

SELECT 'AMI_INTERVAL_READINGS generated: ' || COUNT(*) || ' rows' AS status FROM AMI_INTERVAL_READINGS;

-- ============================================================================
-- STEP 9: Load TECHNICAL_MANUALS_PDF_CHUNKS from parquet
-- ============================================================================
-- Technical manuals for RAG-based document search

CREATE TABLE IF NOT EXISTS PRODUCTION.TECHNICAL_MANUALS_PDF_CHUNKS (
    CHUNK_ID NUMBER,
    DOCUMENT_ID VARCHAR(100),
    CHUNK_TEXT VARCHAR(16777216),
    DOCUMENT_TYPE VARCHAR(200),
    SOURCE_SYSTEM VARCHAR(100) DEFAULT 'TECHNICAL_MANUALS_PDF',
    LANGUAGE VARCHAR(10) DEFAULT 'en',
    LANGUAGE_NAME VARCHAR(50) DEFAULT 'English',
    LANGUAGE_NATIVE VARCHAR(50) DEFAULT 'English'
);

-- Define parquet file format
CREATE OR REPLACE FILE FORMAT PARQUET_FORMAT
    TYPE = 'PARQUET';

-- Load technical manuals from parquet (if file exists in stage)
COPY INTO PRODUCTION.TECHNICAL_MANUALS_PDF_CHUNKS (
    CHUNK_ID, DOCUMENT_ID, CHUNK_TEXT, DOCUMENT_TYPE, 
    SOURCE_SYSTEM, LANGUAGE, LANGUAGE_NAME, LANGUAGE_NATIVE
)
FROM (
    SELECT 
        $1:CHUNK_ID::NUMBER,
        $1:DOCUMENT_ID::VARCHAR,
        $1:CHUNK_TEXT::VARCHAR,
        $1:DOCUMENT_TYPE::VARCHAR,
        $1:SOURCE_SYSTEM::VARCHAR,
        $1:LANGUAGE::VARCHAR,
        $1:LANGUAGE_NAME::VARCHAR,
        $1:LANGUAGE_NATIVE::VARCHAR
    FROM @SEED_DATA_STAGE/technical_manuals/
)
FILE_FORMAT = PARQUET_FORMAT
ON_ERROR = 'CONTINUE';

SELECT 'TECHNICAL_MANUALS_PDF_CHUNKS loaded: ' || COUNT(*) || ' rows' AS status FROM PRODUCTION.TECHNICAL_MANUALS_PDF_CHUNKS;

-- ============================================================================
-- STEP 10: Summary
-- ============================================================================
SELECT '=== SEED DATA LOADING COMPLETE ===' AS message;

SELECT 
    'SUBSTATIONS' AS table_name, COUNT(*) AS row_count FROM SUBSTATIONS
UNION ALL
SELECT 'TRANSFORMER_METADATA', COUNT(*) FROM TRANSFORMER_METADATA
UNION ALL
SELECT 'METER_INFRASTRUCTURE', COUNT(*) FROM METER_INFRASTRUCTURE
UNION ALL
SELECT 'CUSTOMERS_MASTER_DATA', COUNT(*) FROM CUSTOMERS_MASTER_DATA
UNION ALL
SELECT 'AMI_INTERVAL_READINGS', COUNT(*) FROM AMI_INTERVAL_READINGS
UNION ALL
SELECT 'TECHNICAL_MANUALS_PDF_CHUNKS', COUNT(*) FROM PRODUCTION.TECHNICAL_MANUALS_PDF_CHUNKS;
