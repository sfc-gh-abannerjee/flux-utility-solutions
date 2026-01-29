-- =============================================================================
-- export_seed_data.sql
-- Export seed data from SOURCE_DATABASE to a stage for redistribution
-- =============================================================================
-- Purpose: Create seed data files that can be loaded into new deployments
-- Run this ONCE to generate seed data files
--
-- Usage:
--   snow sql -f scripts/seed/export_seed_data.sql
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SOURCE_DATABASE;
USE SCHEMA PRODUCTION;
USE WAREHOUSE SI_DEMO_WH;

-- =============================================================================
-- Step 1: Create export stage
-- =============================================================================

CREATE STAGE IF NOT EXISTS SOURCE_DATABASE.PRODUCTION.FLUX_SEED_EXPORT
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Stage for exporting seed data';

-- =============================================================================
-- Step 2: Export core reference tables (small, full export)
-- =============================================================================

-- SUBSTATIONS (275 rows) - Full export
COPY INTO @FLUX_SEED_EXPORT/substations/
FROM (
    SELECT 
        SUBSTATION_ID,
        SUBSTATION_NAME,
        LATITUDE,
        LONGITUDE,
        VOLTAGE_KV,
        CAPACITY_MVA,
        REGION,
        DISTRICT,
        COMMISSION_DATE,
        STATUS
    FROM SUBSTATIONS
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE;

-- TRANSFORMER_METADATA (91K rows) - Full export  
COPY INTO @FLUX_SEED_EXPORT/transformers/
FROM (
    SELECT 
        TRANSFORMER_ID,
        SUBSTATION_ID,
        CIRCUIT_ID,
        TRANSFORMER_TYPE,
        CAPACITY_KVA,
        VOLTAGE_PRIMARY,
        VOLTAGE_SECONDARY,
        LATITUDE,
        LONGITUDE,
        INSTALL_DATE,
        MANUFACTURER,
        MODEL,
        HEALTH_SCORE,
        RISK_CATEGORY,
        LAST_MAINTENANCE_DATE
    FROM TRANSFORMER_METADATA
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE
MAX_FILE_SIZE = 104857600;

-- CIRCUIT_METADATA (8.8K rows) - Full export
COPY INTO @FLUX_SEED_EXPORT/circuits/
FROM (
    SELECT 
        CIRCUIT_ID,
        CIRCUIT_NAME,
        SUBSTATION_ID,
        VOLTAGE_LEVEL,
        CIRCUIT_TYPE,
        TOTAL_LENGTH_MILES,
        CONDUCTOR_TYPE,
        INSTALL_DATE,
        STATUS
    FROM CIRCUIT_METADATA
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE;

-- =============================================================================
-- Step 3: Export operational tables (sampled for size)
-- =============================================================================

-- METER_INFRASTRUCTURE - Sample 50K for small seed
COPY INTO @FLUX_SEED_EXPORT/meters_small/
FROM (
    SELECT 
        METER_ID,
        TRANSFORMER_ID,
        CUSTOMER_ID,
        METER_TYPE,
        MANUFACTURER,
        MODEL,
        INSTALL_DATE,
        LATITUDE,
        LONGITUDE,
        SERVICE_VOLTAGE,
        METER_STATUS
    FROM METER_INFRASTRUCTURE
    SAMPLE (50000 ROWS)
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE;

-- CUSTOMERS_MASTER_DATA - Sample 50K for small seed
COPY INTO @FLUX_SEED_EXPORT/customers_small/
FROM (
    SELECT 
        CUSTOMER_ID,
        ACCOUNT_NUMBER,
        CUSTOMER_NAME,
        CUSTOMER_TYPE,
        SERVICE_ADDRESS,
        CITY,
        STATE,
        ZIP_CODE,
        LATITUDE,
        LONGITUDE,
        RATE_CLASS,
        ACCOUNT_STATUS,
        SERVICE_START_DATE,
        METER_ID
    FROM CUSTOMERS_MASTER_DATA
    SAMPLE (50000 ROWS)
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE;

-- =============================================================================
-- Step 4: Verify exports
-- =============================================================================

SELECT 'Seed data exported to stage' AS status;

LS @FLUX_SEED_EXPORT/;

-- =============================================================================
-- Step 5: Create manifest
-- =============================================================================

SELECT OBJECT_CONSTRUCT(
    'exported_at', CURRENT_TIMESTAMP(),
    'source_database', 'SOURCE_DATABASE',
    'files', ARRAY_CONSTRUCT(
        OBJECT_CONSTRUCT('path', 'substations/', 'table', 'SUBSTATIONS', 'rows', 275),
        OBJECT_CONSTRUCT('path', 'transformers/', 'table', 'TRANSFORMER_METADATA', 'rows', 91554),
        OBJECT_CONSTRUCT('path', 'circuits/', 'table', 'CIRCUIT_METADATA', 'rows', 8842),
        OBJECT_CONSTRUCT('path', 'meters_small/', 'table', 'METER_INFRASTRUCTURE', 'rows', 50000),
        OBJECT_CONSTRUCT('path', 'customers_small/', 'table', 'CUSTOMERS_MASTER_DATA', 'rows', 50000)
    )
) AS manifest;
