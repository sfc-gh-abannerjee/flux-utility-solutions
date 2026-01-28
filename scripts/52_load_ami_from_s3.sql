-- =============================================================================
-- 52_load_ami_from_s3.sql
-- Load AMI_INTERVAL_READINGS from External S3 Stage
-- =============================================================================
-- Purpose: Load the full 7.1B row AMI time-series dataset from S3
-- 
-- Data Location: s3://{{ s3_bucket }}/raw/ami/ami_interval_readings/
-- Total Size: ~78.7 GB (385 parquet files)
-- Row Count: 7,105,569,024 rows
-- Date Range: July 2024 - August 2025 (14 months)
-- 
-- Prerequisites:
--   - External stage access configured (or use provided integration)
--   - Target table AMI_INTERVAL_READINGS created
--   - XLARGE warehouse recommended for optimal performance
--
-- Usage:
--   snow sql -c <connection> -f scripts/52_load_ami_from_s3.sql \
--       -D "database=FLUX_PROD" -D "warehouse=FLUX_LARGE"
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE WAREHOUSE IDENTIFIER('<% warehouse %>');
USE SCHEMA PRODUCTION;

-- -----------------------------------------------------------------------------
-- 1. CREATE EXTERNAL STAGE (if not exists)
-- -----------------------------------------------------------------------------
-- This creates a reference to the S3 bucket containing AMI data
-- The bucket is publicly readable for Flux deployments

CREATE STAGE IF NOT EXISTS AMI_EXTERNAL_STAGE
    URL = 's3://{{ s3_bucket }}/raw/ami/ami_interval_readings/'
    FILE_FORMAT = (TYPE = PARQUET)
    COMMENT = 'External stage for AMI interval readings (7.1B rows, 78.7GB)';

-- -----------------------------------------------------------------------------
-- 2. VERIFY STAGE ACCESS
-- -----------------------------------------------------------------------------

SELECT 'Checking external stage access...' AS status;

-- List files to verify access (show first 10)
LS @AMI_EXTERNAL_STAGE PATTERN='.*parquet' ;

-- -----------------------------------------------------------------------------
-- 3. CREATE TARGET TABLE (if not exists)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS AMI_INTERVAL_READINGS (
    METER_ID VARCHAR NOT NULL,
    TIMESTAMP TIMESTAMP_NTZ NOT NULL,
    USAGE_KWH FLOAT,
    VOLTAGE NUMBER(22,0),
    POWER_FACTOR NUMBER(23,2),
    CUSTOMER_SEGMENT_ID VARCHAR(11),
    SOURCE_TABLE VARCHAR
)
CLUSTER BY (DATE_TRUNC('DAY', TIMESTAMP), METER_ID)
COMMENT = 'AMI interval readings - 7.1B rows, 15-minute granularity';

-- -----------------------------------------------------------------------------
-- 4. LOAD DATA FROM EXTERNAL STAGE
-- -----------------------------------------------------------------------------

SELECT 'Loading AMI data from S3 (this may take 15-30 minutes)...' AS status;
SELECT CURRENT_TIMESTAMP() AS load_start_time;

-- Use COPY INTO for efficient parallel loading
COPY INTO AMI_INTERVAL_READINGS
FROM @AMI_EXTERNAL_STAGE
FILE_FORMAT = (TYPE = PARQUET)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = 'CONTINUE';

SELECT CURRENT_TIMESTAMP() AS load_end_time;

-- -----------------------------------------------------------------------------
-- 5. VERIFY LOAD
-- -----------------------------------------------------------------------------

SELECT 
    'AMI_INTERVAL_READINGS' AS table_name,
    COUNT(*) AS rows_loaded,
    MIN(TIMESTAMP) AS min_timestamp,
    MAX(TIMESTAMP) AS max_timestamp,
    COUNT(DISTINCT METER_ID) AS distinct_meters
FROM AMI_INTERVAL_READINGS;

-- -----------------------------------------------------------------------------
-- 6. CREATE USEFUL VIEWS
-- -----------------------------------------------------------------------------

-- Sample view for recent data
CREATE OR REPLACE VIEW AMI_RECENT_24H AS
SELECT *
FROM AMI_INTERVAL_READINGS
WHERE TIMESTAMP >= DATEADD('day', -1, CURRENT_TIMESTAMP());

-- Hourly aggregation view
CREATE OR REPLACE VIEW AMI_HOURLY_SUMMARY AS
SELECT 
    DATE_TRUNC('hour', TIMESTAMP) AS hour,
    COUNT(*) AS reading_count,
    COUNT(DISTINCT METER_ID) AS active_meters,
    AVG(USAGE_KWH) AS avg_usage_kwh,
    SUM(USAGE_KWH) AS total_usage_kwh,
    AVG(VOLTAGE) AS avg_voltage
FROM AMI_INTERVAL_READINGS
GROUP BY 1;

SELECT 'AMI data load complete!' AS status;

-- =============================================================================
-- LOAD COMPLETE
-- Expected: 7,105,569,024 rows from ~597,000 meters over 14 months
-- =============================================================================
