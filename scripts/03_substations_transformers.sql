-- =============================================================================
-- 03_substations_transformers.sql
-- Flux Utility Solutions - Grid Foundation Tables (Substations & Transformers)
-- =============================================================================
-- Purpose: Create core grid infrastructure tables
-- Dependencies: 01_database_infrastructure.sql
-- Jinja2 Variables:
--   <% database %>   - Target database name
--   <% warehouse %>  - Target warehouse name
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE WAREHOUSE IDENTIFIER('<% warehouse %>');
USE SCHEMA PRODUCTION;

-- -----------------------------------------------------------------------------
-- 1. SUBSTATIONS
-- -----------------------------------------------------------------------------
-- 275 substations serving the Houston metropolitan area
-- Naming convention: SUB-HOU-XXX

CREATE OR ALTER TABLE SUBSTATIONS (
    -- Primary key
    SUBSTATION_ID VARCHAR(20) NOT NULL PRIMARY KEY,
    
    -- Basic attributes
    SUBSTATION_NAME VARCHAR(100),
    REGION VARCHAR(50),
    SUBSTATION_TYPE VARCHAR(20),  -- TRANSMISSION, DISTRIBUTION, SWITCHING
    VOLTAGE_LEVEL VARCHAR(10),    -- 345KV, 138KV, 69KV, etc.
    
    -- Location
    LATITUDE FLOAT NOT NULL,
    LONGITUDE FLOAT NOT NULL,
    LOCATION_COORDINATE VARCHAR(100),
    DISTANCE_FROM_COAST_MILE NUMBER(10,1),
    
    -- Capacity & Load
    CAPACITY_MVA NUMBER(10,0),
    CURRENT_LOAD_MW NUMBER(10,2),
    PEAK_LOAD_MW NUMBER(10,2),
    N_MINUS_1_CONTINGENCY_RATING_MW NUMBER(10,2),
    LOAD_FACTOR_PCT NUMBER(5,2),
    
    -- Operations
    COMMISSIONED_DATE DATE,
    OPERATIONAL_STATUS VARCHAR(20),  -- OPERATIONAL, MAINTENANCE, OFFLINE
    LAST_INSPECTION_DATE DATE,
    CRITICAL_INFRASTRUCTURE_FLAG BOOLEAN DEFAULT FALSE,
    
    -- Audit
    ENTITY_ID NUMBER(18,0),
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (REGION, SUBSTATION_TYPE)
COMMENT = 'Distribution and transmission substations - 275 assets serving Houston metro';

-- -----------------------------------------------------------------------------
-- 2. TRANSFORMER_METADATA
-- -----------------------------------------------------------------------------
-- ~91,000 distribution transformers
-- Naming convention: XFMR-HOU-XXXXXX or SYNTH-XFMR-XXX
-- Note: Uses CREATE TABLE IF NOT EXISTS because CREATE OR ALTER doesn't support computed columns
-- Schema matches PRODUCTION.TRANSFORMER_METADATA exactly

CREATE TABLE IF NOT EXISTS TRANSFORMER_METADATA (
    -- Primary key
    TRANSFORMER_ID VARCHAR(16777216),
    
    -- Location
    LATITUDE FLOAT,
    LONGITUDE FLOAT,
    
    -- Topology references
    SUBSTATION_ID VARCHAR(16777216),
    CIRCUIT_ID VARCHAR(16777216),
    
    -- Specifications
    RATED_KVA NUMBER(4,0),
    PRIMARY_VOLTAGE_KV NUMBER(5,2),
    PHASE_CODE VARCHAR(3),
    MANUFACTURER VARCHAR(50),
    MODEL_NUMBER VARCHAR(50),
    
    -- Operations
    INSTALL_YEAR NUMBER(4,0),
    LAST_MAINTENANCE_DATE DATE,
    HEALTH_SCORE FLOAT,
    
    -- Load metrics
    CURRENT_LOAD_KVA NUMBER(20,1),
    PEAK_LOAD_KVA NUMBER(20,1),
    LOAD_UTILIZATION_PCT NUMBER(28,2),
    METER_COUNT NUMBER(18,0),
    
    -- CIM-compliant fields
    TRANSFORMER_ROLE VARCHAR(20),
    PARENT_TRANSFORMER_ID VARCHAR(50),
    
    -- Computed columns for semantic view compatibility
    -- 2026-07-29: this was a VIRTUAL column,
    --   AGE_YEARS NUMBER(5,0) AS (YEAR(CURRENT_DATE()) - INSTALL_YEAR)
    -- which Snowflake rejects outright:
    --   "Invalid usage of CURRENT_DATE non deterministic function in AGE_YEARS
    --    virtual column definition."
    -- Virtual columns must be deterministic. It is now a plain column that loaders
    -- populate as YEAR(CURRENT_DATE()) - INSTALL_YEAR at insert time. Readers are
    -- unaffected: models/utility_semantic_model.yaml and scripts/11_ml_feature_tables.sql
    -- both just SELECT AGE_YEARS, and a stored column satisfies them identically.
    AGE_YEARS NUMBER(5,0),

    LOCATION_AREA VARCHAR(17) AS (
        CASE 
            WHEN LATITUDE < 29.4 THEN 'Coastal Texas'
            WHEN LATITUDE < 29.8 AND LONGITUDE > -95.3 THEN 'Houston Metro'
            WHEN LATITUDE >= 29.8 THEN 'Montgomery County'
            ELSE 'Harris County'
        END
    ),
    -- 2026-07-29: this was FEEDER_ID VARCHAR(16777216) AS ('FEEDER-' || COALESCE(RIGHT(CIRCUIT_ID, 3), '000'))
    -- and it made the whole script fail on a fresh deploy:
    --   "Data type of virtual column does not match the data type of its expression for
    --    column 'FEEDER_ID'. Expected VARCHAR(16777216), found VARCHAR(16777223)."
    -- RIGHT() does not narrow its argument, so it returns max VARCHAR, and prefixing 7
    -- characters pushes the inferred length 7 past the maximum. A virtual column's
    -- declared type must match its expression exactly, so cast the expression to the
    -- same right-sized type. The value is at most 10 characters ('FEEDER-' + 3).
    FEEDER_ID VARCHAR(20) AS (('FEEDER-' || COALESCE(RIGHT(CIRCUIT_ID, 3), '000'))::VARCHAR(20)),

    ASSET_ID VARCHAR(16777216) AS (TRANSFORMER_ID),
    LOAD_SERVING_CLASS VARCHAR(11) AS (
        CASE
            WHEN LOAD_UTILIZATION_PCT < 50 THEN 'Residential'
            WHEN LOAD_UTILIZATION_PCT < 75 THEN 'Commercial'
            ELSE 'Industrial'
        END
    )
)
CLUSTER BY (SUBSTATION_ID, CIRCUIT_ID)
COMMENT = 'Distribution transformers - 91,000 assets with CIM-compliant topology';

-- -----------------------------------------------------------------------------
-- 3. CIRCUIT_METADATA
-- -----------------------------------------------------------------------------
-- ~8,800 distribution circuits (feeders)

CREATE OR ALTER TABLE CIRCUIT_METADATA (
    -- Primary key
    CIRCUIT_ID VARCHAR(20) NOT NULL PRIMARY KEY,
    
    -- Topology
    SUBSTATION_ID VARCHAR(20) REFERENCES SUBSTATIONS(SUBSTATION_ID),
    FEEDER_NAME VARCHAR(100),
    
    -- Specifications
    VOLTAGE_LEVEL VARCHAR(10),
    PHASE_CONFIGURATION VARCHAR(10),
    LINE_LENGTH_MILES NUMBER(10,2),
    
    -- Load
    RATED_CAPACITY_MW NUMBER(10,2),
    PEAK_LOAD_MW NUMBER(10,2),
    CUSTOMER_COUNT NUMBER(10,0),
    TRANSFORMER_COUNT NUMBER(10,0),
    
    -- Operations
    OPERATIONAL_STATUS VARCHAR(20),
    AUTOMATION_LEVEL VARCHAR(20),  -- MANUAL, SEMI_AUTO, FULLY_AUTO
    
    -- Audit
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Distribution circuits/feeders - 8,800 circuits';

-- -----------------------------------------------------------------------------
-- 4. VERIFICATION
-- -----------------------------------------------------------------------------

SELECT 'SUBSTATIONS' as table_name, COUNT(*) as row_count FROM SUBSTATIONS
UNION ALL
SELECT 'TRANSFORMER_METADATA', COUNT(*) FROM TRANSFORMER_METADATA
UNION ALL
SELECT 'CIRCUIT_METADATA', COUNT(*) FROM CIRCUIT_METADATA;

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 04_meters_infrastructure.sql to create meter tables
-- =============================================================================
