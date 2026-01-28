-- ============================================================================
-- Flux Utility Solutions: ML Model Registry
-- ============================================================================
-- Script: 20_model_registry.sql
-- Purpose: Set up Snowflake Model Registry for ML model versioning
--
-- Features:
-- - Model versioning and lifecycle management
-- - Experiment tracking
-- - Model deployment targets
-- ============================================================================

USE DATABASE <% database %>;
USE SCHEMA <% schema %>;
USE WAREHOUSE <% warehouse %>;

-- ============================================================================
-- Model Registry Schema
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS ML_REGISTRY;

-- ============================================================================
-- Model Metadata Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS ML_REGISTRY.MODEL_CATALOG (
    model_id VARCHAR(100) PRIMARY KEY,
    model_name VARCHAR(255) NOT NULL,
    model_version VARCHAR(50) NOT NULL,
    model_type VARCHAR(100),  -- 'classification', 'regression', 'anomaly_detection'
    description TEXT,
    
    -- Training info
    trained_at TIMESTAMP_NTZ,
    trained_by VARCHAR(100),
    training_dataset VARCHAR(255),
    training_rows NUMBER,
    
    -- Performance metrics
    accuracy FLOAT,
    precision_score FLOAT,
    recall_score FLOAT,
    f1_score FLOAT,
    auc_roc FLOAT,
    rmse FLOAT,
    mae FLOAT,
    
    -- Deployment status
    deployment_status VARCHAR(50) DEFAULT 'REGISTERED',  -- REGISTERED, STAGING, PRODUCTION, ARCHIVED
    deployed_at TIMESTAMP_NTZ,
    
    -- Audit
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    UNIQUE (model_name, model_version)
);

-- ============================================================================
-- Model Artifacts Storage
-- ============================================================================

CREATE STAGE IF NOT EXISTS ML_REGISTRY.MODEL_ARTIFACTS
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

-- ============================================================================
-- Experiment Tracking
-- ============================================================================

CREATE TABLE IF NOT EXISTS ML_REGISTRY.EXPERIMENTS (
    experiment_id VARCHAR(100) PRIMARY KEY,
    experiment_name VARCHAR(255) NOT NULL,
    model_id VARCHAR(100) REFERENCES ML_REGISTRY.MODEL_CATALOG(model_id),
    
    -- Hyperparameters (stored as JSON)
    hyperparameters VARIANT,
    
    -- Metrics (stored as JSON for flexibility)
    metrics VARIANT,
    
    -- Run info
    started_at TIMESTAMP_NTZ,
    completed_at TIMESTAMP_NTZ,
    duration_seconds NUMBER,
    status VARCHAR(50),  -- RUNNING, COMPLETED, FAILED
    
    -- Notes
    notes TEXT,
    tags ARRAY,
    
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================================
-- Feature Importance Tracking
-- ============================================================================

CREATE TABLE IF NOT EXISTS ML_REGISTRY.FEATURE_IMPORTANCE (
    model_id VARCHAR(100) REFERENCES ML_REGISTRY.MODEL_CATALOG(model_id),
    feature_name VARCHAR(255),
    importance_score FLOAT,
    importance_rank NUMBER,
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    PRIMARY KEY (model_id, feature_name)
);

-- ============================================================================
-- Model Predictions Log
-- ============================================================================

CREATE TABLE IF NOT EXISTS ML_REGISTRY.PREDICTION_LOG (
    prediction_id VARCHAR(100) PRIMARY KEY,
    model_id VARCHAR(100),
    model_version VARCHAR(50),
    
    -- Input/Output
    input_features VARIANT,
    prediction VARIANT,
    confidence FLOAT,
    
    -- Metadata
    predicted_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    latency_ms NUMBER,
    
    -- Feedback (for retraining)
    actual_outcome VARIANT,
    feedback_provided_at TIMESTAMP_NTZ,
    is_correct BOOLEAN
);

-- ============================================================================
-- Register Production Models
-- ============================================================================

-- Transformer Health Prediction Model
INSERT INTO ML_REGISTRY.MODEL_CATALOG (
    model_id, model_name, model_version, model_type, description,
    trained_at, training_dataset, training_rows,
    accuracy, f1_score, auc_roc,
    deployment_status
) VALUES (
    'TRF-HEALTH-001',
    'transformer_health_predictor',
    '1.0.0',
    'classification',
    'Predicts transformer failure risk based on telemetry, age, and load patterns',
    CURRENT_TIMESTAMP(),
    'TRANSFORMER_TELEMETRY_HOURLY',
    211000000,
    0.94,
    0.91,
    0.96,
    'PRODUCTION'
);

-- Customer Segmentation Model
INSERT INTO ML_REGISTRY.MODEL_CATALOG (
    model_id, model_name, model_version, model_type, description,
    trained_at, training_dataset, training_rows,
    deployment_status
) VALUES (
    'CUST-SEG-001',
    'customer_usage_segmentation',
    '1.0.0',
    'clustering',
    'K-means clustering of customers by usage patterns for rate optimization',
    CURRENT_TIMESTAMP(),
    'CUSTOMER_USAGE_FEATURES',
    686000,
    'PRODUCTION'
);

-- Load Forecasting Model
INSERT INTO ML_REGISTRY.MODEL_CATALOG (
    model_id, model_name, model_version, model_type, description,
    trained_at, training_dataset, training_rows,
    rmse, mae,
    deployment_status
) VALUES (
    'LOAD-FCST-001',
    'hourly_load_forecast',
    '1.0.0',
    'time_series',
    'ARIMA-based hourly load forecasting by substation',
    CURRENT_TIMESTAMP(),
    'AMI_INTERVAL_READINGS',
    7100000000,
    125.5,
    89.2,
    'PRODUCTION'
);

-- ============================================================================
-- Model Deployment View
-- ============================================================================

CREATE OR REPLACE VIEW ML_REGISTRY.V_PRODUCTION_MODELS AS
SELECT 
    model_id,
    model_name,
    model_version,
    model_type,
    description,
    trained_at,
    training_rows,
    COALESCE(accuracy, auc_roc, 1 - (rmse/1000)) as primary_metric,
    deployed_at
FROM ML_REGISTRY.MODEL_CATALOG
WHERE deployment_status = 'PRODUCTION';

-- ============================================================================
-- Grant Permissions
-- ============================================================================

GRANT USAGE ON SCHEMA ML_REGISTRY TO ROLE <% user_role %>;
GRANT SELECT ON ALL TABLES IN SCHEMA ML_REGISTRY TO ROLE <% user_role %>;
GRANT SELECT ON ALL VIEWS IN SCHEMA ML_REGISTRY TO ROLE <% user_role %>;

SELECT 'ML Model Registry setup complete' AS status;
