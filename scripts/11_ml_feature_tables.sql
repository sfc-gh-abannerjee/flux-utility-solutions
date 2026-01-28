-- =============================================================================
-- 11_ml_feature_tables.sql
-- Flux Utility Solutions - Machine Learning Feature Tables
-- =============================================================================
-- Purpose: Create feature tables for ML model training and inference
-- Dependencies: 06_ami_readings_pipeline.sql, 07_aggregation_tables.sql
-- Jinja2 Variables:
--   <% database %>  - Target database name
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE SCHEMA PRODUCTION;

-- -----------------------------------------------------------------------------
-- 1. TRANSFORMER FAILURE PREDICTION FEATURES
-- -----------------------------------------------------------------------------
-- Feature table for transformer failure prediction model

CREATE TABLE IF NOT EXISTS ML_TRANSFORMER_FEATURES (
    FEATURE_ID VARCHAR(50) DEFAULT UUID_STRING(),
    TRANSFORMER_ID VARCHAR(50) NOT NULL,
    FEATURE_DATE DATE NOT NULL,
    
    -- Load Features
    AVG_LOAD_FACTOR_7D FLOAT,
    MAX_LOAD_FACTOR_7D FLOAT,
    LOAD_FACTOR_STDDEV_7D FLOAT,
    OVERLOAD_HOURS_7D NUMBER(10,0),
    AVG_LOAD_FACTOR_30D FLOAT,
    MAX_LOAD_FACTOR_30D FLOAT,
    OVERLOAD_HOURS_30D NUMBER(10,0),
    
    -- Thermal Stress Features
    THERMAL_STRESS_HOURS_HIGH NUMBER(10,0),
    THERMAL_STRESS_HOURS_CRITICAL NUMBER(10,0),
    MAX_TEMPERATURE_7D FLOAT,
    COOLING_CYCLES_7D NUMBER(10,0),
    
    -- Age and Health Features
    AGE_YEARS NUMBER(5,2),
    HEALTH_SCORE NUMBER(5,2),
    DAYS_SINCE_MAINTENANCE NUMBER(10,0),
    MAINTENANCE_COUNT_YTD NUMBER(10,0),
    
    -- Environmental Features  
    AVG_AMBIENT_TEMP_7D FLOAT,
    MAX_AMBIENT_TEMP_7D FLOAT,
    HUMIDITY_PCT_AVG FLOAT,
    
    -- Target Variable (for training)
    FAILED_WITHIN_30D BOOLEAN,
    FAILURE_DATE DATE,
    
    -- Metadata
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    PRIMARY KEY (TRANSFORMER_ID, FEATURE_DATE)
)
CLUSTER BY (FEATURE_DATE, TRANSFORMER_ID)
COMMENT = 'ML features for transformer failure prediction model';

-- Populate features from aggregation tables
CREATE OR REPLACE PROCEDURE REFRESH_TRANSFORMER_FEATURES()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Refresh ML_TRANSFORMER_FEATURES from source tables'
AS
$$
BEGIN
    MERGE INTO ML_TRANSFORMER_FEATURES tgt
    USING (
        SELECT 
            t.TRANSFORMER_ID,
            CURRENT_DATE() as FEATURE_DATE,
            -- Load metrics
            AVG(h.LOAD_FACTOR_PCT) as AVG_LOAD_FACTOR_7D,
            MAX(h.LOAD_FACTOR_PCT) as MAX_LOAD_FACTOR_7D,
            STDDEV(h.LOAD_FACTOR_PCT) as LOAD_FACTOR_STDDEV_7D,
            SUM(CASE WHEN h.IS_OVERLOADED THEN 1 ELSE 0 END) as OVERLOAD_HOURS_7D,
            -- Transformer metadata
            t.AGE_YEARS,
            t.HEALTH_SCORE,
            0 as DAYS_SINCE_MAINTENANCE, -- Placeholder
            0 as MAINTENANCE_COUNT_YTD,  -- Placeholder
            FALSE as FAILED_WITHIN_30D,
            NULL as FAILURE_DATE
        FROM TRANSFORMER_METADATA t
        LEFT JOIN TRANSFORMER_HOURLY_LOAD h 
            ON t.TRANSFORMER_ID = h.TRANSFORMER_ID
            AND h.LOAD_HOUR >= DATEADD('day', -7, CURRENT_TIMESTAMP())
        GROUP BY t.TRANSFORMER_ID, t.AGE_YEARS, t.HEALTH_SCORE
    ) src
    ON tgt.TRANSFORMER_ID = src.TRANSFORMER_ID 
       AND tgt.FEATURE_DATE = src.FEATURE_DATE
    WHEN MATCHED THEN UPDATE SET
        AVG_LOAD_FACTOR_7D = src.AVG_LOAD_FACTOR_7D,
        MAX_LOAD_FACTOR_7D = src.MAX_LOAD_FACTOR_7D,
        LOAD_FACTOR_STDDEV_7D = src.LOAD_FACTOR_STDDEV_7D,
        OVERLOAD_HOURS_7D = src.OVERLOAD_HOURS_7D,
        AGE_YEARS = src.AGE_YEARS,
        HEALTH_SCORE = src.HEALTH_SCORE
    WHEN NOT MATCHED THEN INSERT (
        TRANSFORMER_ID, FEATURE_DATE, AVG_LOAD_FACTOR_7D, MAX_LOAD_FACTOR_7D,
        LOAD_FACTOR_STDDEV_7D, OVERLOAD_HOURS_7D, AGE_YEARS, HEALTH_SCORE,
        DAYS_SINCE_MAINTENANCE, MAINTENANCE_COUNT_YTD, FAILED_WITHIN_30D, FAILURE_DATE
    ) VALUES (
        src.TRANSFORMER_ID, src.FEATURE_DATE, src.AVG_LOAD_FACTOR_7D, src.MAX_LOAD_FACTOR_7D,
        src.LOAD_FACTOR_STDDEV_7D, src.OVERLOAD_HOURS_7D, src.AGE_YEARS, src.HEALTH_SCORE,
        src.DAYS_SINCE_MAINTENANCE, src.MAINTENANCE_COUNT_YTD, src.FAILED_WITHIN_30D, src.FAILURE_DATE
    );
    
    RETURN 'Features refreshed for ' || (SELECT COUNT(DISTINCT TRANSFORMER_ID) FROM ML_TRANSFORMER_FEATURES) || ' transformers';
END;
$$;

-- -----------------------------------------------------------------------------
-- 2. CUSTOMER LOAD FORECASTING FEATURES
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ML_LOAD_FORECAST_FEATURES (
    FEATURE_ID VARCHAR(50) DEFAULT UUID_STRING(),
    METER_ID VARCHAR(50) NOT NULL,
    FEATURE_DATE DATE NOT NULL,
    FEATURE_HOUR NUMBER(2,0) NOT NULL,
    
    -- Lag Features (prior usage)
    USAGE_LAG_1H FLOAT,
    USAGE_LAG_24H FLOAT,
    USAGE_LAG_168H FLOAT,  -- 1 week ago
    
    -- Rolling Statistics
    USAGE_AVG_24H FLOAT,
    USAGE_MAX_24H FLOAT,
    USAGE_STDDEV_24H FLOAT,
    USAGE_AVG_7D FLOAT,
    
    -- Calendar Features
    DAY_OF_WEEK NUMBER(1,0),
    IS_WEEKEND BOOLEAN,
    IS_HOLIDAY BOOLEAN,
    MONTH NUMBER(2,0),
    
    -- Weather Features (if available)
    TEMPERATURE_F FLOAT,
    HUMIDITY_PCT FLOAT,
    CLOUD_COVER_PCT FLOAT,
    
    -- Customer Segment
    CUSTOMER_SEGMENT VARCHAR(50),
    
    -- Target Variable
    ACTUAL_USAGE_KWH FLOAT,
    
    -- Metadata
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    PRIMARY KEY (METER_ID, FEATURE_DATE, FEATURE_HOUR)
)
CLUSTER BY (FEATURE_DATE, METER_ID)
COMMENT = 'ML features for load forecasting model';

-- -----------------------------------------------------------------------------
-- 3. OUTAGE PREDICTION FEATURES  
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ML_OUTAGE_PREDICTION_FEATURES (
    FEATURE_ID VARCHAR(50) DEFAULT UUID_STRING(),
    CIRCUIT_ID VARCHAR(50) NOT NULL,
    FEATURE_DATETIME TIMESTAMP_NTZ NOT NULL,
    
    -- Grid State Features
    METER_COUNT NUMBER(10,0),
    METERS_REPORTING NUMBER(10,0),
    REPORTING_RATE FLOAT,
    AVG_VOLTAGE FLOAT,
    VOLTAGE_STDDEV FLOAT,
    LOW_VOLTAGE_METER_COUNT NUMBER(10,0),
    
    -- Historical Outage Features
    OUTAGES_LAST_30D NUMBER(10,0),
    OUTAGES_LAST_90D NUMBER(10,0),
    AVG_OUTAGE_DURATION_MIN FLOAT,
    
    -- Weather Features
    WIND_SPEED_MPH FLOAT,
    PRECIPITATION_IN FLOAT,
    STORM_PROXIMITY_MILES FLOAT,
    
    -- Target Variables
    HAD_OUTAGE_WITHIN_4H BOOLEAN,
    OUTAGE_START_TIME TIMESTAMP_NTZ,
    OUTAGE_DURATION_MIN FLOAT,
    
    -- Metadata
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    PRIMARY KEY (CIRCUIT_ID, FEATURE_DATETIME)
)
CLUSTER BY (FEATURE_DATETIME, CIRCUIT_ID)
COMMENT = 'ML features for outage prediction model';

-- -----------------------------------------------------------------------------
-- 4. MODEL REGISTRY TABLE
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ML_MODEL_REGISTRY (
    MODEL_ID VARCHAR(50) PRIMARY KEY DEFAULT UUID_STRING(),
    MODEL_NAME VARCHAR(100) NOT NULL,
    MODEL_VERSION VARCHAR(20) NOT NULL,
    MODEL_TYPE VARCHAR(50) NOT NULL,  -- TRANSFORMER_FAILURE, LOAD_FORECAST, OUTAGE_PREDICTION
    
    -- Model Performance
    TRAIN_DATE DATE,
    TRAIN_ROWS NUMBER(15,0),
    ACCURACY FLOAT,
    PRECISION_SCORE FLOAT,
    RECALL_SCORE FLOAT,
    F1_SCORE FLOAT,
    MAE FLOAT,  -- For regression models
    RMSE FLOAT,
    
    -- Model Storage
    MODEL_STAGE_PATH VARCHAR(500),
    MODEL_SIZE_MB FLOAT,
    
    -- Status
    STATUS VARCHAR(20) DEFAULT 'TRAINING',  -- TRAINING, VALIDATED, DEPLOYED, RETIRED
    DEPLOYED_AT TIMESTAMP_NTZ,
    RETIRED_AT TIMESTAMP_NTZ,
    
    -- Metadata
    CREATED_BY VARCHAR(100),
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    UNIQUE (MODEL_NAME, MODEL_VERSION)
)
COMMENT = 'Registry for ML models deployed in Snowflake';

-- -----------------------------------------------------------------------------
-- 5. PREDICTION OUTPUT TABLES
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ML_TRANSFORMER_PREDICTIONS (
    PREDICTION_ID VARCHAR(50) DEFAULT UUID_STRING(),
    MODEL_ID VARCHAR(50) REFERENCES ML_MODEL_REGISTRY(MODEL_ID),
    TRANSFORMER_ID VARCHAR(50) NOT NULL,
    PREDICTION_DATE DATE NOT NULL,
    
    -- Predictions
    FAILURE_PROBABILITY FLOAT,
    RISK_CATEGORY VARCHAR(20),  -- LOW, MODERATE, HIGH, CRITICAL
    RECOMMENDED_ACTION VARCHAR(500),
    
    -- Feature Importance (top 5)
    TOP_FEATURES VARIANT,
    
    -- Metadata
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    PRIMARY KEY (TRANSFORMER_ID, PREDICTION_DATE)
)
COMMENT = 'Transformer failure predictions from ML model';

CREATE TABLE IF NOT EXISTS ML_LOAD_FORECASTS (
    FORECAST_ID VARCHAR(50) DEFAULT UUID_STRING(),
    MODEL_ID VARCHAR(50),
    METER_ID VARCHAR(50) NOT NULL,
    FORECAST_DATETIME TIMESTAMP_NTZ NOT NULL,
    
    -- Forecasts
    PREDICTED_USAGE_KWH FLOAT,
    PREDICTION_LOWER_BOUND FLOAT,
    PREDICTION_UPPER_BOUND FLOAT,
    CONFIDENCE_LEVEL FLOAT,
    
    -- Actual (filled in after observation)
    ACTUAL_USAGE_KWH FLOAT,
    PREDICTION_ERROR FLOAT,
    
    -- Metadata
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    PRIMARY KEY (METER_ID, FORECAST_DATETIME)
)
COMMENT = 'Load forecasts from ML model';

-- -----------------------------------------------------------------------------
-- 6. GRANTS
-- -----------------------------------------------------------------------------

GRANT SELECT ON ALL TABLES IN SCHEMA PRODUCTION TO ROLE IDENTIFIER('<% user_role %>');
GRANT SELECT, INSERT ON ML_TRANSFORMER_PREDICTIONS TO ROLE IDENTIFIER('<% admin_role %>');
GRANT SELECT, INSERT ON ML_LOAD_FORECASTS TO ROLE IDENTIFIER('<% admin_role %>');

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 12_postgres_instance.sql for transactional database setup
-- =============================================================================
