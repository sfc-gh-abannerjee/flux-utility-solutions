-- =============================================================================
-- 07_aggregation_tables.sql
-- Flux Utility Solutions - Transformer Load and Thermal Stress Tables
-- =============================================================================
-- Purpose: Create aggregated transformer loading and thermal analysis tables
-- Dependencies: 06_ami_readings_pipeline.sql, 03_substations_transformers.sql
-- Jinja2 Variables:
--   <% database %>   - Target database name
--   <% warehouse %>  - Target warehouse name
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE WAREHOUSE IDENTIFIER('<% warehouse %>');
USE SCHEMA PRODUCTION;

-- -----------------------------------------------------------------------------
-- 1. TRANSFORMER_HOURLY_LOAD
-- -----------------------------------------------------------------------------
-- 211 MILLION rows - Hourly aggregation of transformer loading
-- Computed from AMI readings joined to transformer assignments

CREATE OR ALTER TABLE TRANSFORMER_HOURLY_LOAD (
    -- Keys
    TRANSFORMER_ID VARCHAR(50) NOT NULL,
    LOAD_HOUR TIMESTAMP_NTZ NOT NULL,
    
    -- Load metrics
    TOTAL_KWH NUMBER(15,2),
    LOAD_KW NUMBER(10,2),
    METER_COUNT NUMBER(10,0),
    AVG_METER_KWH NUMBER(10,4),
    
    -- Capacity metrics (from transformer metadata)
    RATED_KVA NUMBER(10,0),
    LOAD_FACTOR_PCT NUMBER(6,2),  -- (LOAD_KW / RATED_KVA) * 100
    
    -- Overload indicators
    IS_OVERLOADED BOOLEAN,  -- LOAD_FACTOR_PCT > 100
    OVERLOAD_DURATION_HOURS NUMBER(5,0),  -- Running count of consecutive overload hours
    
    -- Thermal stress category
    THERMAL_STRESS_CATEGORY VARCHAR(20),  -- LOW, MODERATE, HIGH, CRITICAL
    
    PRIMARY KEY (TRANSFORMER_ID, LOAD_HOUR)
)
CLUSTER BY (DATE_TRUNC('DAY', LOAD_HOUR), TRANSFORMER_ID)
COMMENT = 'Hourly transformer loading - 211M rows for capacity planning';

-- -----------------------------------------------------------------------------
-- 2. TRANSFORMER_THERMAL_STRESS_MATERIALIZED
-- -----------------------------------------------------------------------------
-- 198 MILLION rows - Materialized thermal stress analysis
-- Used for predictive maintenance ML models

CREATE OR ALTER TABLE TRANSFORMER_THERMAL_STRESS_MATERIALIZED (
    -- Keys
    TRANSFORMER_ID VARCHAR(50) NOT NULL,
    STRESS_HOUR TIMESTAMP_NTZ NOT NULL,
    
    -- Load context
    LOAD_KW NUMBER(10,2),
    RATED_KVA NUMBER(10,0),
    LOAD_FACTOR_PCT NUMBER(6,2),
    
    -- Thermal metrics
    AMBIENT_TEMP_F NUMBER(5,1),  -- From weather data
    TOP_OIL_TEMP_F NUMBER(5,1),  -- Estimated
    HOT_SPOT_TEMP_F NUMBER(5,1), -- Estimated
    
    -- Stress indicators
    THERMAL_STRESS_SCORE NUMBER(5,2),  -- 0-100 composite score
    STRESS_CATEGORY VARCHAR(20),
    CONSECUTIVE_STRESS_HOURS NUMBER(5,0),
    
    -- Time context
    IS_PEAK_HOUR BOOLEAN,
    HOUR_OF_DAY NUMBER(2,0),
    DAY_OF_WEEK NUMBER(1,0),
    
    PRIMARY KEY (TRANSFORMER_ID, STRESS_HOUR)
)
CLUSTER BY (DATE_TRUNC('DAY', STRESS_HOUR), TRANSFORMER_ID)
COMMENT = 'Transformer thermal stress analysis - 198M rows for ML training';

-- -----------------------------------------------------------------------------
-- 3. TRANSFORMER_LOCATION_GROUPS
-- -----------------------------------------------------------------------------
-- Spatial grouping of transformers for map visualization

CREATE OR ALTER TABLE TRANSFORMER_LOCATION_GROUPS (
    GROUP_ID VARCHAR(50) NOT NULL PRIMARY KEY,
    SUBSTATION_ID VARCHAR(20),
    CIRCUIT_ID VARCHAR(20),
    
    -- Bounding box
    MIN_LAT FLOAT,
    MAX_LAT FLOAT,
    MIN_LON FLOAT,
    MAX_LON FLOAT,
    CENTER_LAT FLOAT,
    CENTER_LON FLOAT,
    
    -- Aggregates
    TRANSFORMER_COUNT NUMBER(10,0),
    TOTAL_CAPACITY_KVA NUMBER(15,0),
    AVG_HEALTH_SCORE NUMBER(5,2),
    
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Transformer spatial groupings for map clustering';

-- -----------------------------------------------------------------------------
-- 4. ASSET_HEALTH_HISTORY
-- -----------------------------------------------------------------------------
-- 5 MILLION rows - Historical health score tracking

CREATE OR ALTER TABLE ASSET_HEALTH_HISTORY (
    RECORD_ID NUMBER(18,0) AUTOINCREMENT PRIMARY KEY,
    ASSET_TYPE VARCHAR(20),  -- TRANSFORMER, POLE, METER, SUBSTATION
    ASSET_ID VARCHAR(50),
    RECORDED_DATE DATE,
    
    -- Health metrics
    HEALTH_SCORE NUMBER(5,2),
    PREVIOUS_SCORE NUMBER(5,2),
    SCORE_CHANGE NUMBER(5,2),
    
    -- Contributing factors
    LOAD_FACTOR_AVG NUMBER(5,2),
    MAINTENANCE_OVERDUE_DAYS NUMBER(5,0),
    AGE_YEARS NUMBER(3,0),
    OUTAGE_COUNT NUMBER(5,0),
    
    -- Categorization
    HEALTH_CATEGORY VARCHAR(20),  -- GOOD, FAIR, POOR, CRITICAL
    ALERT_FLAG BOOLEAN
)
CLUSTER BY (ASSET_TYPE, RECORDED_DATE)
COMMENT = 'Historical asset health scores - 5M rows for trend analysis';

-- -----------------------------------------------------------------------------
-- 5. EQUIPMENT_HEALTH_SCORECARD
-- -----------------------------------------------------------------------------
-- Current health scorecard view

CREATE OR ALTER VIEW APPLICATIONS.EQUIPMENT_HEALTH_SCORECARD AS
SELECT 
    'TRANSFORMER' as ASSET_TYPE,
    TRANSFORMER_ID as ASSET_ID,
    HEALTH_SCORE,
    AGE_YEARS,
    LOAD_UTILIZATION_PCT,
    CASE 
        WHEN HEALTH_SCORE >= 80 THEN 'GOOD'
        WHEN HEALTH_SCORE >= 60 THEN 'FAIR'
        WHEN HEALTH_SCORE >= 40 THEN 'POOR'
        ELSE 'CRITICAL'
    END as HEALTH_CATEGORY,
    CASE 
        WHEN HEALTH_SCORE < 50 AND LOAD_UTILIZATION_PCT > 80 THEN TRUE 
        ELSE FALSE 
    END as REQUIRES_ATTENTION
FROM PRODUCTION.TRANSFORMER_METADATA
WHERE HEALTH_SCORE IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 6. VERIFICATION
-- -----------------------------------------------------------------------------

SELECT 'TRANSFORMER_HOURLY_LOAD' as table_name, COUNT(*) as row_count FROM TRANSFORMER_HOURLY_LOAD
UNION ALL
SELECT 'TRANSFORMER_THERMAL_STRESS_MATERIALIZED', COUNT(*) FROM TRANSFORMER_THERMAL_STRESS_MATERIALIZED
UNION ALL
SELECT 'ASSET_HEALTH_HISTORY', COUNT(*) FROM ASSET_HEALTH_HISTORY;

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 08_semantic_view.sql to create Cortex Analyst semantic layer
-- =============================================================================
