-- =============================================================================
-- SPCS Deployment Script for FLUX Data Forge with Snowpipe Streaming
-- =============================================================================
-- Prerequisites:
-- 1. RSA key pair generated (see setup_keypair_auth.sql)
-- 2. AMI_STREAMING_USER created with RSA public key
-- 3. AMI_STREAMING_KEY secret created with private key
-- 4. Docker image built and pushed to repository

USE ROLE SYSADMIN;
USE DATABASE SI_DEMOS;
USE SCHEMA PRODUCTION;
USE WAREHOUSE SI_DEMO_WH;

-- =============================================================================
-- Step 1: Create Image Repository (if not exists)
-- =============================================================================
CREATE IMAGE REPOSITORY IF NOT EXISTS AMI_STREAMING_REPO;

-- Get the registry URL for docker push
SHOW IMAGE REPOSITORIES LIKE 'AMI_STREAMING_REPO' IN SCHEMA SI_DEMOS.PRODUCTION;

-- =============================================================================
-- Step 2: Create Target Table for Streaming Data
-- =============================================================================
CREATE TABLE IF NOT EXISTS AMI_STREAMING_READINGS (
    METER_ID VARCHAR(50),
    READING_TIMESTAMP TIMESTAMP_NTZ,
    USAGE_KWH FLOAT,
    VOLTAGE FLOAT,
    CUSTOMER_SEGMENT VARCHAR(50),
    TRANSFORMER_ID VARCHAR(50),
    SUBSTATION_ID VARCHAR(50),
    SERVICE_AREA VARCHAR(50),
    TEMPERATURE_C FLOAT,
    IS_OUTAGE BOOLEAN,
    DATA_QUALITY VARCHAR(20),
    INGESTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Add clustering for optimal query performance
ALTER TABLE AMI_STREAMING_READINGS CLUSTER BY (READING_TIMESTAMP, METER_ID);

-- =============================================================================
-- Step 3: Create Compute Pool (if not exists)
-- =============================================================================
CREATE COMPUTE POOL IF NOT EXISTS FLUX_DATA_FORGE_POOL
    MIN_NODES = 1
    MAX_NODES = 2
    INSTANCE_FAMILY = CPU_X64_S
    AUTO_RESUME = TRUE
    AUTO_SUSPEND_SECS = 300;

-- =============================================================================
-- Step 4: Create the SPCS Service
-- =============================================================================
-- First, drop existing service if it exists
DROP SERVICE IF EXISTS FLUX_DATA_FORGE_SERVICE;

-- Create the service with secrets mount and external access for Postgres
CREATE SERVICE FLUX_DATA_FORGE_SERVICE
    IN COMPUTE POOL FLUX_DATA_FORGE_POOL
    FROM SPECIFICATION $
spec:
  containers:
    - name: flux-data-forge
      image: /SI_DEMOS/PRODUCTION/AMI_STREAMING_REPO/flux_data_forge:latest
      env:
        SNOWFLAKE_ACCOUNT: {{ account }}
        SNOWFLAKE_USER: AMI_STREAMING_USER
        SNOWFLAKE_DATABASE: SI_DEMOS
        SNOWFLAKE_SCHEMA: PRODUCTION
        SNOWFLAKE_ROLE: SYSADMIN
        SNOWFLAKE_WAREHOUSE: SI_DEMO_WH
        # PostgreSQL Configuration - Snowflake Managed Postgres
        POSTGRES_HOST: {{ postgres_host }}
        POSTGRES_DATABASE: postgres
        POSTGRES_USER: application
        POSTGRES_PORT: "5432"
        # AMI Streaming Configuration
        AMI_TABLE: AMI_STREAMING_READINGS
        AMI_PIPE: AMI_STREAMING_PIPE
        SERVICE_AREA: HOUSTON_METRO
      secrets:
        - snowflakeSecret: SI_DEMOS.PRODUCTION.AMI_STREAMING_KEY
          directoryPath: '/usr/local/creds'
        - snowflakeSecret: SI_DEMOS.PRODUCTION.POSTGRES_CREDENTIALS
          secretKeyRef: password
          envVarName: POSTGRES_PASSWORD
      resources:
        requests:
          cpu: 1
          memory: 2Gi
        limits:
          cpu: 2
          memory: 4Gi
  endpoints:
    - name: app
      port: 8501
      public: true
$
    EXTERNAL_ACCESS_INTEGRATIONS = (PYPI_ACCESS_INTEGRATION, SNOWFLAKE_API_INTEGRATION, GOOGLE_FONTS_EAI, FLUX_POSTGRES_INTEGRATION)
    MIN_INSTANCES = 1
    MAX_INSTANCES = 1
    COMMENT = 'FLUX Data Forge - AMI Streaming with Snowpipe and PostgreSQL support';

-- =============================================================================
-- Step 5: Grant Access
-- =============================================================================
GRANT USAGE ON SERVICE FLUX_DATA_FORGE_SERVICE TO ROLE ACCOUNTADMIN;

-- =============================================================================
-- Step 6: Check Service Status
-- =============================================================================
SHOW SERVICES LIKE 'FLUX_DATA_FORGE_SERVICE';
DESCRIBE SERVICE FLUX_DATA_FORGE_SERVICE;

-- Get the endpoint URL
SELECT SYSTEM$GET_SERVICE_STATUS('FLUX_DATA_FORGE_SERVICE');

-- =============================================================================
-- Step 7: View Service Logs (for debugging)
-- =============================================================================
-- SELECT SYSTEM$GET_SERVICE_LOGS('FLUX_DATA_FORGE_SERVICE', 'flux-data-forge', 0, 100);
