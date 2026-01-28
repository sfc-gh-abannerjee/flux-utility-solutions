/*
================================================================================
FLUX UTILITY SOLUTIONS - DATA EXPORT SCRIPT
================================================================================
This script exports all production data from SI_DEMOS to compressed Parquet files
that can be bundled with the repository.

RUN THIS SCRIPT TO EXPORT ALL DATA:
  snow sql -f seed_data/export_all_data.sql -c <your_connection>

The exported files will be in the @FLUX_EXPORT_STAGE stage.
Download them using: snow stage get @SI_DEMOS.PRODUCTION.FLUX_EXPORT_STAGE/ seed_data/full/
================================================================================
*/

USE DATABASE SI_DEMOS;
USE SCHEMA PRODUCTION;
USE WAREHOUSE SI_DEMO_WH;

-- Create export stage
CREATE OR REPLACE STAGE FLUX_EXPORT_STAGE
    FILE_FORMAT = (TYPE = 'PARQUET')
    COMMENT = 'Stage for exporting seed data to Parquet format';

-- ============================================================================
-- EXPORT SUBSTATIONS (275 rows)
-- ============================================================================
COPY INTO @FLUX_EXPORT_STAGE/substations/
FROM (
    SELECT 
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
    FROM SUBSTATIONS
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE;

SELECT 'Exported SUBSTATIONS: ' || COUNT(*) || ' rows' AS status FROM SUBSTATIONS;

-- ============================================================================
-- EXPORT CIRCUIT_METADATA (8,842 rows)
-- ============================================================================
COPY INTO @FLUX_EXPORT_STAGE/circuits/
FROM (
    SELECT *
    FROM CIRCUIT_METADATA
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE;

SELECT 'Exported CIRCUIT_METADATA: ' || COUNT(*) || ' rows' AS status FROM CIRCUIT_METADATA;

-- ============================================================================
-- EXPORT TRANSFORMER_METADATA (91,554 rows)
-- ============================================================================
COPY INTO @FLUX_EXPORT_STAGE/transformers/
FROM (
    SELECT *
    FROM TRANSFORMER_METADATA
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE;

SELECT 'Exported TRANSFORMER_METADATA: ' || COUNT(*) || ' rows' AS status FROM TRANSFORMER_METADATA;

-- ============================================================================
-- EXPORT METER_INFRASTRUCTURE (596,906 rows)
-- ============================================================================
COPY INTO @FLUX_EXPORT_STAGE/meters/
FROM (
    SELECT *
    FROM METER_INFRASTRUCTURE
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE
MAX_FILE_SIZE = 104857600;  -- 100MB chunks

SELECT 'Exported METER_INFRASTRUCTURE: ' || COUNT(*) || ' rows' AS status FROM METER_INFRASTRUCTURE;

-- ============================================================================
-- EXPORT CUSTOMERS_MASTER_DATA (686,359 rows)
-- ============================================================================
COPY INTO @FLUX_EXPORT_STAGE/customers/
FROM (
    SELECT 
        CUSTOMER_ID,
        FIRST_NAME,
        LAST_NAME,
        FULL_NAME,
        PRIMARY_METER_ID,
        CUSTOMER_SEGMENT,
        SERVICE_ADDRESS,
        SERVICE_COUNTY,
        PHONE,
        EMAIL,
        ACCOUNT_STATUS,
        SERVICE_START_DATE,
        CREATED_AT,
        DATA_SOURCE,
        ZIP_CODE,
        CITY
    FROM CUSTOMERS_MASTER_DATA
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE
MAX_FILE_SIZE = 104857600;

SELECT 'Exported CUSTOMERS_MASTER_DATA: ' || COUNT(*) || ' rows' AS status FROM CUSTOMERS_MASTER_DATA;

-- ============================================================================
-- EXPORT WORK_ORDERS (93,678 rows)
-- ============================================================================
COPY INTO @FLUX_EXPORT_STAGE/work_orders/
FROM (
    SELECT *
    FROM WORK_ORDERS
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE;

SELECT 'Exported WORK_ORDERS: ' || COUNT(*) || ' rows' AS status FROM WORK_ORDERS;

-- ============================================================================
-- EXPORT OUTAGE_EVENTS (34,252 rows)
-- ============================================================================
COPY INTO @FLUX_EXPORT_STAGE/outage_events/
FROM (
    SELECT *
    FROM OUTAGE_EVENTS
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE;

SELECT 'Exported OUTAGE_EVENTS: ' || COUNT(*) || ' rows' AS status FROM OUTAGE_EVENTS;

-- ============================================================================
-- EXPORT VOLTAGE_SAG_EVENTS (72,550 rows)
-- ============================================================================
COPY INTO @FLUX_EXPORT_STAGE/voltage_events/
FROM (
    SELECT *
    FROM VOLTAGE_SAG_EVENTS
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE;

SELECT 'Exported VOLTAGE_SAG_EVENTS: ' || COUNT(*) || ' rows' AS status FROM VOLTAGE_SAG_EVENTS;

-- ============================================================================
-- EXPORT WEATHER_EVENTS (31 rows)
-- ============================================================================
COPY INTO @FLUX_EXPORT_STAGE/weather_events/
FROM (
    SELECT *
    FROM WEATHER_EVENTS
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE;

SELECT 'Exported WEATHER_EVENTS: ' || COUNT(*) || ' rows' AS status FROM WEATHER_EVENTS;

-- ============================================================================
-- EXPORT GRID_POWER_LINES (13,104 rows)
-- ============================================================================
COPY INTO @FLUX_EXPORT_STAGE/power_lines/
FROM (
    SELECT *
    FROM GRID_POWER_LINES
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE;

SELECT 'Exported GRID_POWER_LINES: ' || COUNT(*) || ' rows' AS status FROM GRID_POWER_LINES;

-- ============================================================================
-- EXPORT GRID_POLES_INFRASTRUCTURE (62,038 rows)
-- ============================================================================
COPY INTO @FLUX_EXPORT_STAGE/poles/
FROM (
    SELECT *
    FROM GRID_POLES_INFRASTRUCTURE
)
FILE_FORMAT = (TYPE = 'PARQUET')
HEADER = TRUE
OVERWRITE = TRUE;

SELECT 'Exported GRID_POLES_INFRASTRUCTURE: ' || COUNT(*) || ' rows' AS status FROM GRID_POLES_INFRASTRUCTURE;

-- ============================================================================
-- LIST EXPORTED FILES
-- ============================================================================
SELECT 'Export complete! Files available in @FLUX_EXPORT_STAGE' AS status;

LIST @FLUX_EXPORT_STAGE;

/*
================================================================================
DOWNLOAD INSTRUCTIONS
================================================================================
After running this script, download the Parquet files using Snowflake CLI:

  cd flux-utility-solutions
  snow stage get @SI_DEMOS.PRODUCTION.FLUX_EXPORT_STAGE/ seed_data/full/ --recursive

Or using SnowSQL:
  
  GET @SI_DEMOS.PRODUCTION.FLUX_EXPORT_STAGE/ file://seed_data/full/;

The Parquet files can then be loaded into any Snowflake account using:
  
  PUT file://seed_data/full/*.parquet @DATABASE.SCHEMA.SEED_STAGE/;
  COPY INTO TABLE FROM @SEED_STAGE FILE_FORMAT = (TYPE = PARQUET);
================================================================================
*/
