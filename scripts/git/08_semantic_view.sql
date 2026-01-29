--!jinja2
-- =============================================================================
-- 08_semantic_view.sql (Git Integration Version)
-- Flux Utility Solutions - Cortex Analyst Semantic View Deployment
-- =============================================================================
-- Purpose: Deploy semantic view for natural language analytics
-- Dependencies: All PRODUCTION tables (01-07)
-- 
-- Variable Templating (Standard Jinja2 for Git Integration):
--   {{ database }}    - Target database name (e.g., FLUX_DEMO)
--   {{ user_role }}   - Role to grant access (optional, defaults to PUBLIC)
--
-- Usage with Git Integration:
--   EXECUTE IMMEDIATE FROM @repo/branches/main/scripts/git/08_semantic_view.sql
--       USING (database => 'FLUX_DEV', user_role => 'FLUX_DEV_USER');
--
-- Usage with Snow CLI:
--   snow sql -f scripts/git/08_semantic_view.sql --enable-template-syntax=JINJA \
--       -D "database=FLUX_DEV" -D "user_role=FLUX_DEV_USER"
--
-- =============================================================================

{% set user_role = user_role | default('PUBLIC') %}

USE DATABASE IDENTIFIER('{{ database }}');
USE SCHEMA APPLICATIONS;

-- -----------------------------------------------------------------------------
-- 1. CREATE SEMANTIC VIEW
-- -----------------------------------------------------------------------------

CREATE OR REPLACE SEMANTIC VIEW UTILITY_SEMANTIC_VIEW
TABLES (
    -- AMI Readings table
    ami AS {{ database }}.PRODUCTION.AMI_READINGS_FINAL
        WITH SYNONYMS = ('meter readings', 'interval data', 'energy data'),
    
    -- Customers table - note UNIQUE constraint on PRIMARY_METER_ID for relationship
    customers AS {{ database }}.PRODUCTION.CUSTOMERS_MASTER_DATA
        PRIMARY KEY (CUSTOMER_ID)
        UNIQUE (PRIMARY_METER_ID)
        WITH SYNONYMS = ('customer profiles', 'accounts'),
    
    -- Transformer hourly load
    xfmr_load AS {{ database }}.PRODUCTION.TRANSFORMER_HOURLY_LOAD
        WITH SYNONYMS = ('transformer loading', 'hourly load'),
    
    -- Transformer metadata
    xfmr AS {{ database }}.PRODUCTION.TRANSFORMER_METADATA
        PRIMARY KEY (TRANSFORMER_ID)
        WITH SYNONYMS = ('transformers', 'transformer assets')
)
RELATIONSHIPS (
    ami(METER_ID) REFERENCES customers(PRIMARY_METER_ID),
    xfmr_load(TRANSFORMER_ID) REFERENCES xfmr(TRANSFORMER_ID)
)
FACTS (
    ami.USAGE_KWH AS USAGE_KWH 
        WITH SYNONYMS = ('consumption', 'energy usage', 'kwh')
        COMMENT = 'Energy consumption in kilowatt-hours',
    ami.VOLTAGE AS VOLTAGE
        WITH SYNONYMS = ('volts', 'voltage reading')
        COMMENT = 'Voltage reading in volts',
    xfmr_load.LOAD_KW AS LOAD_KW
        WITH SYNONYMS = ('load', 'power')
        COMMENT = 'Current load in kilowatts',
    xfmr_load.LOAD_FACTOR_PCT AS LOAD_FACTOR_PCT
        WITH SYNONYMS = ('utilization', 'loading percent')
        COMMENT = 'Load as percentage of rated capacity',
    xfmr.HEALTH_SCORE AS HEALTH_SCORE
        COMMENT = 'Asset health score 0-100',
    xfmr.AGE_YEARS AS AGE_YEARS
        COMMENT = 'Transformer age in years',
    xfmr.RATED_KVA AS RATED_KVA
        WITH SYNONYMS = ('capacity', 'rating')
        COMMENT = 'Rated capacity in kVA'
)
DIMENSIONS (
    ami.METER_ID AS METER_ID
        WITH SYNONYMS = ('meter', 'meter number')
        COMMENT = 'Unique smart meter identifier',
    ami.TIMESTAMP AS TIMESTAMP
        WITH SYNONYMS = ('reading time', 'time', 'date')
        COMMENT = '15-minute interval timestamp',
    customers.CUSTOMER_ID AS CUSTOMER_ID
        WITH SYNONYMS = ('customer', 'account')
        COMMENT = 'Unique customer identifier',
    customers.FULL_NAME AS FULL_NAME
        WITH SYNONYMS = ('name', 'customer name')
        COMMENT = 'Customer full name',
    customers.CITY AS CITY
        COMMENT = 'Service city',
    customers.ZIP_CODE AS ZIP_CODE
        WITH SYNONYMS = ('zip', 'postal code')
        COMMENT = 'Service ZIP code',
    customers.CUSTOMER_SEGMENT AS CUSTOMER_SEGMENT
        WITH SYNONYMS = ('segment', 'type')
        COMMENT = 'Customer type (RESIDENTIAL, COMMERCIAL, INDUSTRIAL)',
    xfmr.TRANSFORMER_ID AS TRANSFORMER_ID
        WITH SYNONYMS = ('transformer', 'xfmr')
        COMMENT = 'Transformer identifier',
    xfmr.LOCATION_AREA AS LOCATION_AREA
        COMMENT = 'Geographic area',
    xfmr.SUBSTATION_ID AS SUBSTATION_ID
        COMMENT = 'Parent substation',
    xfmr.CIRCUIT_ID AS CIRCUIT_ID
        COMMENT = 'Circuit/feeder assignment',
    xfmr_load.THERMAL_STRESS_CATEGORY AS THERMAL_STRESS_CATEGORY
        WITH SYNONYMS = ('stress level', 'thermal risk')
        COMMENT = 'Thermal stress category (LOW, MODERATE, HIGH, CRITICAL)',
    xfmr_load.LOAD_HOUR AS LOAD_HOUR
        WITH SYNONYMS = ('hour')
        COMMENT = 'Hour of measurement'
)
METRICS (
    ami.TOTAL_CONSUMPTION AS SUM(ami.USAGE_KWH)
        WITH SYNONYMS = ('total kwh', 'total usage')
        COMMENT = 'Total energy consumption in kWh',
    ami.AVG_CONSUMPTION AS AVG(ami.USAGE_KWH)
        WITH SYNONYMS = ('average kwh', 'avg usage')
        COMMENT = 'Average energy consumption per interval',
    ami.METER_COUNT AS COUNT(DISTINCT ami.METER_ID)
        COMMENT = 'Count of distinct meters reporting',
    ami.AVG_VOLTAGE AS AVG(ami.VOLTAGE)
        COMMENT = 'Average voltage across readings',
    customers.CUSTOMER_COUNT AS COUNT(DISTINCT customers.CUSTOMER_ID)
        COMMENT = 'Total number of customers',
    xfmr.TRANSFORMER_COUNT AS COUNT(DISTINCT xfmr.TRANSFORMER_ID)
        COMMENT = 'Total transformers',
    xfmr.AVG_AGE AS AVG(xfmr.AGE_YEARS)
        COMMENT = 'Average transformer age',
    xfmr.AVG_HEALTH_SCORE AS AVG(xfmr.HEALTH_SCORE)
        COMMENT = 'Average health score',
    xfmr_load.AVG_LOAD_FACTOR AS AVG(xfmr_load.LOAD_FACTOR_PCT)
        COMMENT = 'Average load factor percentage',
    xfmr_load.PEAK_LOAD_FACTOR AS MAX(xfmr_load.LOAD_FACTOR_PCT)
        COMMENT = 'Maximum load factor percentage'
)
COMMENT = 'Utility grid analytics semantic model for AMI readings, transformer health, and customer profiles.';

-- -----------------------------------------------------------------------------
-- 2. GRANT ACCESS TO USER ROLE
-- -----------------------------------------------------------------------------

GRANT SELECT ON SEMANTIC VIEW UTILITY_SEMANTIC_VIEW 
    TO ROLE IDENTIFIER('{{ user_role }}');

-- -----------------------------------------------------------------------------
-- 3. VERIFY DEPLOYMENT
-- -----------------------------------------------------------------------------

SHOW SEMANTIC VIEWS IN SCHEMA APPLICATIONS;

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- =============================================================================
