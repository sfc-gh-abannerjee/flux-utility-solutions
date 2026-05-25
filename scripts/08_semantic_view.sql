-- =============================================================================
-- 08_semantic_view.sql
-- Flux Utility Solutions - Cortex Analyst Semantic View Deployment
-- =============================================================================
-- Purpose: Deploy semantic view for natural language analytics
-- Dependencies: All PRODUCTION tables (01-07)
-- 
-- Variable Templating (Snow CLI Jinja2):
--   <% database %>   - Target database name (e.g., FLUX_DEMO)
--   <% warehouse %>  - Target warehouse name
--   <% user_role %>  - Role to grant SELECT on semantic view (default: PUBLIC)
--
-- Usage:
--   snow sql -f scripts/08_semantic_view.sql \
--       -D "database=YOUR_DATABASE" -D "warehouse=YOUR_WH"
--   # Optionally override user_role (defaults to PUBLIC):
--   snow sql -f scripts/08_semantic_view.sql \
--       -D "database=YOUR_DATABASE" -D "warehouse=YOUR_WH" -D "user_role=ANALYST_ROLE"
--
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE WAREHOUSE IDENTIFIER('<% warehouse %>');
USE SCHEMA APPLICATIONS;

-- -----------------------------------------------------------------------------
-- 1. CREATE SEMANTIC VIEW
-- -----------------------------------------------------------------------------
-- Using Snowflake DDL syntax (NOT YAML) with:
--   TABLES     - Define logical tables with PRIMARY KEY and UNIQUE constraints
--   RELATIONSHIPS - Define joins between tables
--   FACTS      - Numeric measures
--   DIMENSIONS - Categorical attributes for grouping/filtering
--   METRICS    - Aggregated calculations
--
-- IMPORTANT: The referenced key in RELATIONSHIPS must be PRIMARY KEY or UNIQUE

CREATE OR REPLACE SEMANTIC VIEW UTILITY_SEMANTIC_VIEW
TABLES (
    -- AMI Readings table (actual table: AMI_INTERVAL_READINGS)
    ami AS <% database %>.PRODUCTION.AMI_INTERVAL_READINGS
        WITH SYNONYMS = ('meter readings', 'interval data', 'energy data'),
    
    -- Customers table - UNIQUE on METER_ID (actual col, not PRIMARY_METER_ID)
    customers AS <% database %>.PRODUCTION.CUSTOMERS_MASTER_DATA
        PRIMARY KEY (CUSTOMER_ID)
        UNIQUE (METER_ID)
        WITH SYNONYMS = ('customer profiles', 'accounts'),
    
    -- Transformer hourly load
    xfmr_load AS <% database %>.PRODUCTION.TRANSFORMER_HOURLY_LOAD
        WITH SYNONYMS = ('transformer loading', 'hourly load'),
    
    -- Transformer metadata
    xfmr AS <% database %>.PRODUCTION.TRANSFORMER_METADATA
        PRIMARY KEY (TRANSFORMER_ID)
        WITH SYNONYMS = ('transformers', 'transformer assets')
)
RELATIONSHIPS (
    -- AMI readings link to customers via meter ID
    ami(METER_ID) REFERENCES customers(METER_ID),
    -- Transformer load links to transformer metadata
    xfmr_load(TRANSFORMER_ID) REFERENCES xfmr(TRANSFORMER_ID)
)
FACTS (
    -- Energy consumption facts
    ami.USAGE_KWH AS USAGE_KWH 
        WITH SYNONYMS = ('consumption', 'energy usage', 'kwh')
        COMMENT = 'Energy consumption in kilowatt-hours',
    -- Logical name VOLTAGE maps to actual column VOLTAGE_V
    ami.VOLTAGE AS VOLTAGE_V
        WITH SYNONYMS = ('volts', 'voltage reading')
        COMMENT = 'Voltage reading in volts',
    
    -- Transformer load facts: logical LOAD_KW maps to actual CURRENT_LOAD_KW
    xfmr_load.LOAD_KW AS CURRENT_LOAD_KW
        WITH SYNONYMS = ('load', 'power')
        COMMENT = 'Current load in kilowatts',
    xfmr_load.LOAD_FACTOR_PCT AS LOAD_FACTOR_PCT
        WITH SYNONYMS = ('utilization', 'loading percent')
        COMMENT = 'Load as percentage of rated capacity',
    
    -- Transformer asset facts: logical RATED_KVA maps to actual CAPACITY_KVA
    xfmr.HEALTH_SCORE AS HEALTH_SCORE
        COMMENT = 'Asset health score 0-100',
    xfmr.RATED_KVA AS CAPACITY_KVA
        WITH SYNONYMS = ('capacity', 'rating')
        COMMENT = 'Rated capacity in kVA'
)
DIMENSIONS (
    -- AMI dimensions
    ami.METER_ID AS METER_ID
        WITH SYNONYMS = ('meter', 'meter number')
        COMMENT = 'Unique smart meter identifier',
    ami.READING_TIMESTAMP AS READING_TIMESTAMP
        WITH SYNONYMS = ('reading time', 'time', 'date')
        COMMENT = '15-minute interval timestamp',
    
    -- Customer dimensions
    customers.CUSTOMER_ID AS CUSTOMER_ID
        WITH SYNONYMS = ('customer', 'account')
        COMMENT = 'Unique customer identifier',
    customers.FIRST_NAME AS FIRST_NAME
        COMMENT = 'Customer first name',
    customers.LAST_NAME AS LAST_NAME
        COMMENT = 'Customer last name',
    customers.CITY AS CITY
        COMMENT = 'Service city',
    customers.ZIP_CODE AS ZIP_CODE
        WITH SYNONYMS = ('zip', 'postal code')
        COMMENT = 'Service ZIP code',
    -- Logical name CUSTOMER_SEGMENT maps to actual column CUSTOMER_CLASS
    customers.CUSTOMER_SEGMENT AS CUSTOMER_CLASS
        WITH SYNONYMS = ('segment', 'type', 'customer class')
        COMMENT = 'Customer type (RESIDENTIAL, COMMERCIAL, INDUSTRIAL)',
    
    -- Transformer dimensions
    xfmr.TRANSFORMER_ID AS TRANSFORMER_ID
        WITH SYNONYMS = ('transformer', 'xfmr')
        COMMENT = 'Transformer identifier',
    xfmr.SUBSTATION_ID AS SUBSTATION_ID
        COMMENT = 'Parent substation',
    
    -- Transformer load dimensions
    xfmr_load.LOAD_HOUR AS LOAD_HOUR
        WITH SYNONYMS = ('hour')
        COMMENT = 'Hour of measurement'
)
METRICS (
    -- Energy consumption metrics
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
    
    -- Customer metrics
    customers.CUSTOMER_COUNT AS COUNT(DISTINCT customers.CUSTOMER_ID)
        COMMENT = 'Total number of customers',
    
    -- Transformer metrics
    xfmr.TRANSFORMER_COUNT AS COUNT(DISTINCT xfmr.TRANSFORMER_ID)
        COMMENT = 'Total transformers',
    xfmr.AVG_HEALTH_SCORE AS AVG(xfmr.HEALTH_SCORE)
        COMMENT = 'Average health score',
    
    -- Load metrics
    xfmr_load.AVG_LOAD_FACTOR AS AVG(xfmr_load.LOAD_FACTOR_PCT)
        COMMENT = 'Average load factor percentage',
    xfmr_load.PEAK_LOAD_FACTOR AS MAX(xfmr_load.LOAD_FACTOR_PCT)
        COMMENT = 'Maximum load factor percentage'
)
COMMENT = 'Utility grid analytics semantic model for AMI readings, transformer health, and customer profiles. Covers Houston metro area data from July 2024 - August 2025.';

-- -----------------------------------------------------------------------------
-- 2. GRANT ACCESS TO USER ROLE
-- -----------------------------------------------------------------------------

GRANT SELECT ON SEMANTIC VIEW UTILITY_SEMANTIC_VIEW 
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');

-- -----------------------------------------------------------------------------
-- 3. VERIFY DEPLOYMENT
-- -----------------------------------------------------------------------------

SHOW SEMANTIC VIEWS IN SCHEMA APPLICATIONS;

-- Show semantic view structure
DESCRIBE SEMANTIC VIEW UTILITY_SEMANTIC_VIEW;

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- 
-- The semantic view can be used with:
--   1. Cortex Analyst (via API or Snowsight)
--   2. Cortex Agent (see 10_cortex_agent.sql)
--
-- Next: Run 09_cortex_search_services.sql to create search services
-- =============================================================================
