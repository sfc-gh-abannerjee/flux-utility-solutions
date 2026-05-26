-- =============================================================================
-- 07_outage_semantic_view.sql
-- Flux Utility Solutions — Add OUTAGES logical table to UTILITY_SEMANTIC_VIEW
-- =============================================================================
-- Purpose: Surface 18,689-row OUTAGE_RESTORATION_TRACKER to Cortex Analyst
--          by adding an OUTAGES logical table with full dim/metric coverage.
--
-- Prerequisites: 08_semantic_view.sql deployed, OUTAGE_RESTORATION_TRACKER populated.
--
-- DEPLOYMENT NOTES (discovered empirically 2026-05-26):
--   - Semantic view DDL rejects custom OUTAGE_* prefixed aliases that don't match
--     an actual column name — the engine treats them as auto-namespace conflicts.
--     CAUSE/STATUS use same-name aliases. OUTAGE_* aliases only work when the
--     alias exactly matches the underlying column name (e.g. OUTAGE_ID, OUTAGE_START_TIME).
--   - SUBSTATION_ID/TRANSFORMER_ID omitted from DIMENSIONS: both columns appear
--     in the xfmr table too, and the FK side of a relationship cannot be re-exposed
--     as an independently aliased dimension. Use the outages→xfmr join instead.
--   - OUTAGE_DURATION_MINUTES stays in FACTS (numeric). OUTAGE_HOUR excluded
--     (also numeric; not useful as a dimension).
--   - OUTAGE_HISTORY_SEARCHABLE view (step 1) is preserved for use by the
--     OUTAGE_HISTORY_SEARCH Cortex Search Service (08_outage_history_search.sql).
--     It is NOT used as the backing table for the semantic view.
--
-- Variable Templating (Snow CLI Jinja2):
--   <% database %>   - Target database (e.g., FLUX_DB)
--   <% warehouse %>  - Target warehouse (e.g., FLUX_WH)
--   <% user_role %>  - Role to grant SELECT (default: PUBLIC)
--
-- Usage:
--   snow sql -f scripts/realistic_data/07_outage_semantic_view.sql \
--       -D "database=FLUX_DB" -D "warehouse=FLUX_WH"
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE WAREHOUSE IDENTIFIER('<% warehouse %>');

-- -----------------------------------------------------------------------------
-- 1. CREATE ENRICHED OUTAGE VIEW
--    Used by OUTAGE_HISTORY_SEARCH CSS (08_outage_history_search.sql).
--    Adds SEVERITY, OUTAGE_DATE, OUTAGE_HOUR, SEARCH_TEXT computed columns.
-- -----------------------------------------------------------------------------

USE SCHEMA PRODUCTION;

CREATE OR REPLACE VIEW OUTAGE_HISTORY_SEARCHABLE AS
SELECT
    OUTAGE_ID,
    CIRCUIT_ID,
    SUBSTATION_ID,
    TRANSFORMER_ID,
    OUTAGE_START_TIME,
    OUTAGE_END_TIME,
    STATUS,
    CAUSE,
    AFFECTED_CUSTOMERS,
    AFFECTED_TRANSFORMERS,
    CREW_ASSIGNED,
    ESTIMATED_RESTORATION,
    ACTUAL_RESTORATION,
    OUTAGE_DURATION_MINUTES,
    NOTES,
    CREATED_AT,
    UPDATED_AT,
    -- Derived dimensions for Cortex Search service
    DATE(OUTAGE_START_TIME)                                           AS OUTAGE_DATE,
    HOUR(OUTAGE_START_TIME)                                           AS OUTAGE_HOUR,
    CASE
        WHEN AFFECTED_CUSTOMERS >= 100 THEN 'CRITICAL'
        WHEN AFFECTED_CUSTOMERS >= 10  THEN 'HIGH'
        WHEN AFFECTED_CUSTOMERS >= 2   THEN 'MEDIUM'
        ELSE                                'LOW'
    END                                                               AS SEVERITY,
    -- Full-text search blob for Cortex Search service
    OUTAGE_ID
        || ' ' || COALESCE(CAUSE,          'unknown_cause')
        || ' ' || COALESCE(STATUS,         'unknown_status')
        || ' on substation ' || COALESCE(SUBSTATION_ID,  'unknown_sub')
        || ' transformer '   || COALESCE(TRANSFORMER_ID, 'unknown_xfmr')
        || ' '               || COALESCE(NOTES,           '')          AS SEARCH_TEXT
FROM <% database %>.PRODUCTION.OUTAGE_RESTORATION_TRACKER;

-- Verify
SELECT COUNT(*) AS outage_rows FROM OUTAGE_HISTORY_SEARCHABLE;
-- Expected: 18,689

-- -----------------------------------------------------------------------------
-- 2. CREATE OR REPLACE UTILITY_SEMANTIC_VIEW WITH OUTAGES TABLE ADDED
--    Backs the grid_analyst tool in GRID_INTELLIGENCE_AGENT.
--    See DEPLOYMENT NOTES above for alias constraints.
-- -----------------------------------------------------------------------------

USE SCHEMA APPLICATIONS;

CREATE OR REPLACE SEMANTIC VIEW UTILITY_SEMANTIC_VIEW
TABLES (
    -- Existing tables (unchanged)
    ami AS <% database %>.PRODUCTION.AMI_INTERVAL_READINGS
        WITH SYNONYMS = ('meter readings', 'interval data', 'energy data'),

    customers AS <% database %>.PRODUCTION.CUSTOMERS_MASTER_DATA
        PRIMARY KEY (CUSTOMER_ID)
        UNIQUE (METER_ID)
        WITH SYNONYMS = ('customer profiles', 'accounts'),

    xfmr_load AS <% database %>.PRODUCTION.TRANSFORMER_HOURLY_LOAD
        WITH SYNONYMS = ('transformer loading', 'hourly load'),

    xfmr AS <% database %>.PRODUCTION.TRANSFORMER_METADATA
        PRIMARY KEY (TRANSFORMER_ID)
        WITH SYNONYMS = ('transformers', 'transformer assets'),

    -- NEW: Outage history — backed directly by OUTAGE_RESTORATION_TRACKER
    outages AS <% database %>.PRODUCTION.OUTAGE_RESTORATION_TRACKER
        PRIMARY KEY (OUTAGE_ID)
        WITH SYNONYMS = ('outage', 'outages', 'power outage', 'power outages',
                         'disruption', 'grid disruption')
)
RELATIONSHIPS (
    ami(METER_ID)             REFERENCES customers(METER_ID),
    xfmr_load(TRANSFORMER_ID) REFERENCES xfmr(TRANSFORMER_ID),
    -- Outages join transformer metadata via TRANSFORMER_ID (all 18,689 rows populated)
    outages(TRANSFORMER_ID)   REFERENCES xfmr(TRANSFORMER_ID)
)
FACTS (
    ami.USAGE_KWH AS USAGE_KWH
        WITH SYNONYMS = ('consumption', 'energy usage', 'kwh')
        COMMENT = 'Energy consumption in kilowatt-hours',
    ami.VOLTAGE AS VOLTAGE_V
        WITH SYNONYMS = ('volts', 'voltage reading')
        COMMENT = 'Voltage reading in volts',
    xfmr_load.LOAD_KW AS CURRENT_LOAD_KW
        WITH SYNONYMS = ('load', 'power')
        COMMENT = 'Current load in kilowatts',
    xfmr_load.LOAD_FACTOR_PCT AS LOAD_FACTOR_PCT
        WITH SYNONYMS = ('utilization', 'loading percent')
        COMMENT = 'Load as percentage of rated capacity',
    xfmr.HEALTH_SCORE AS HEALTH_SCORE
        COMMENT = 'Asset health score 0-100',
    xfmr.RATED_KVA AS CAPACITY_KVA
        WITH SYNONYMS = ('capacity', 'rating')
        COMMENT = 'Rated capacity in kVA',
    -- Outage numeric facts
    outages.AFFECTED_CUSTOMERS AS AFFECTED_CUSTOMERS
        WITH SYNONYMS = ('customers affected', 'impacted customers', 'affected customers')
        COMMENT = 'Customers affected by this outage',
    outages.OUTAGE_DURATION_MINUTES AS OUTAGE_DURATION_MINUTES
        WITH SYNONYMS = ('duration', 'outage length', 'restoration time')
        COMMENT = 'Outage duration in minutes'
)
DIMENSIONS (
    ami.METER_ID AS METER_ID
        WITH SYNONYMS = ('meter', 'meter number')
        COMMENT = 'Unique smart meter identifier',
    ami.READING_TIMESTAMP AS READING_TIMESTAMP
        WITH SYNONYMS = ('reading time', 'time', 'date')
        COMMENT = '15-minute interval timestamp',
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
    customers.CUSTOMER_SEGMENT AS CUSTOMER_CLASS
        WITH SYNONYMS = ('segment', 'type', 'customer class')
        COMMENT = 'Customer type (RESIDENTIAL, COMMERCIAL, INDUSTRIAL)',
    xfmr.TRANSFORMER_ID AS TRANSFORMER_ID
        WITH SYNONYMS = ('transformer', 'xfmr')
        COMMENT = 'Transformer identifier',
    xfmr.SUBSTATION_ID AS SUBSTATION_ID
        COMMENT = 'Parent substation',
    xfmr_load.LOAD_HOUR AS LOAD_HOUR
        WITH SYNONYMS = ('hour')
        COMMENT = 'Hour of measurement',
    -- Outage dimensions (VARCHAR only; same-name aliases required by DDL parser)
    outages.OUTAGE_ID AS OUTAGE_ID
        WITH SYNONYMS = ('outage id', 'outage number', 'event id')
        COMMENT = 'Unique outage event identifier',
    outages.CAUSE AS CAUSE
        WITH SYNONYMS = ('outage cause', 'outage reason', 'cause of outage')
        COMMENT = 'Root cause: WEATHER (incl. Beryl), TRANSFORMER_OVERLOAD, VEGETATION',
    outages.STATUS AS STATUS
        WITH SYNONYMS = ('outage status', 'restoration status')
        COMMENT = 'Outage status (ACTIVE, RESTORED)',
    outages.OUTAGE_START_TIME AS OUTAGE_START_TIME
        WITH SYNONYMS = ('outage start', 'outage began', 'disruption start')
        COMMENT = 'Timestamp when outage began (July 2024; Beryl = 2024-07-08)'
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
    xfmr.AVG_HEALTH_SCORE AS AVG(xfmr.HEALTH_SCORE)
        COMMENT = 'Average health score',
    xfmr_load.AVG_LOAD_FACTOR AS AVG(xfmr_load.LOAD_FACTOR_PCT)
        COMMENT = 'Average load factor percentage',
    xfmr_load.PEAK_LOAD_FACTOR AS MAX(xfmr_load.LOAD_FACTOR_PCT)
        COMMENT = 'Maximum load factor percentage',
    -- Outage aggregation metrics
    outages.OUTAGE_COUNT AS COUNT(DISTINCT outages.OUTAGE_ID)
        WITH SYNONYMS = ('number of outages', 'outage count', 'total outages',
                         'how many outages')
        COMMENT = 'Total distinct outage events',
    outages.TOTAL_CUSTOMERS_AFFECTED AS SUM(outages.AFFECTED_CUSTOMERS)
        WITH SYNONYMS = ('total customers affected', 'total impacted')
        COMMENT = 'Sum of customers affected across all outages',
    outages.AVG_OUTAGE_DURATION AS AVG(outages.OUTAGE_DURATION_MINUTES)
        WITH SYNONYMS = ('average duration', 'avg outage time', 'mean restoration time')
        COMMENT = 'Average outage duration in minutes'
)
COMMENT = 'Utility grid analytics: AMI, transformer health, customers, and outage history (18,689 events, July 2024, incl. Hurricane Beryl 2024-07-08). Houston metro area.';

GRANT SELECT ON SEMANTIC VIEW UTILITY_SEMANTIC_VIEW
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');

-- -----------------------------------------------------------------------------
-- 3. VERIFY
-- -----------------------------------------------------------------------------

DESCRIBE SEMANTIC VIEW UTILITY_SEMANTIC_VIEW;

-- Outages by cause (expect WEATHER=13637, TRANSFORMER_OVERLOAD=4812, VEGETATION=240)
SELECT CAUSE, OUTAGE_COUNT, TOTAL_CUSTOMERS_AFFECTED
FROM SEMANTIC_VIEW(
    <% database %>.APPLICATIONS.UTILITY_SEMANTIC_VIEW
    DIMENSIONS CAUSE
    METRICS OUTAGE_COUNT, TOTAL_CUSTOMERS_AFFECTED
)
ORDER BY OUTAGE_COUNT DESC;

-- =============================================================================
-- END
-- Next: Run 08_outage_history_search.sql to create OUTAGE_HISTORY_SEARCH CSS
-- =============================================================================

