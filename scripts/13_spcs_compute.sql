-- =============================================================================
-- 13_spcs_compute.sql
-- Flux Utility Solutions - Snowpark Container Services (SPCS) Setup
-- =============================================================================
-- Purpose: Create compute pools and SPCS services for application layer
-- Dependencies: 01_database_infrastructure.sql
-- Jinja2 Variables:
--   <% database %>      - Target database name
--   <% compute_pool %>  - Compute pool name
--   <% spcs_service %>  - SPCS service name
--   <% admin_role %>    - Admin role
--
-- Note: SPCS applications are in separate repositories:
--   - Flux Ops Center: https://github.com/sfc-gh-abannerjee/flux-ops-center-spcs
--   - Flux Data Forge: https://github.com/sfc-gh-abannerjee/flux-utility-data-forge
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');

-- -----------------------------------------------------------------------------
-- 1. CREATE IMAGE REPOSITORY
-- -----------------------------------------------------------------------------

CREATE IMAGE REPOSITORY IF NOT EXISTS APPLICATIONS.FLUX_IMAGES
    COMMENT = 'Container image repository for Flux application services';

-- Show repository URL for docker push
SHOW IMAGE REPOSITORIES IN SCHEMA APPLICATIONS;

-- -----------------------------------------------------------------------------
-- 2. CREATE COMPUTE POOLS
-- -----------------------------------------------------------------------------

-- Interactive compute pool for user-facing services
CREATE COMPUTE POOL IF NOT EXISTS IDENTIFIER('<% compute_pool %>')
    MIN_NODES = 1
    MAX_NODES = 3
    INSTANCE_FAMILY = CPU_X64_S
    AUTO_SUSPEND_SECS = 3600
    AUTO_RESUME = TRUE
    COMMENT = 'Interactive compute pool for Flux Ops Center and user services';

-- ML compute pool for batch processing
CREATE COMPUTE POOL IF NOT EXISTS FLUX_ML_POOL
    MIN_NODES = 0
    MAX_NODES = 5
    INSTANCE_FAMILY = GPU_NV_S
    AUTO_SUSPEND_SECS = 600
    AUTO_RESUME = TRUE
    COMMENT = 'GPU compute pool for ML model training and inference';

-- Grant usage on compute pools
GRANT USAGE ON COMPUTE POOL IDENTIFIER('<% compute_pool %>') TO ROLE IDENTIFIER('<% admin_role %>');
GRANT USAGE ON COMPUTE POOL FLUX_ML_POOL TO ROLE IDENTIFIER('<% admin_role %>');

-- -----------------------------------------------------------------------------
-- 3. CREATE NETWORK RULES
-- -----------------------------------------------------------------------------

-- External access for APIs and data sources
CREATE OR REPLACE NETWORK RULE FLUX_EXTERNAL_ACCESS_RULE
    TYPE = HOST_PORT
    MODE = EGRESS
    VALUE_LIST = (
        'api.weather.gov:443',      -- Weather data
        'nominatim.openstreetmap.org:443',  -- Geocoding
        '0.0.0.0:443',              -- General HTTPS
        '0.0.0.0:80'                -- General HTTP
    )
    COMMENT = 'External network access for Flux services';

-- Create external access integration
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION FLUX_EXTERNAL_ACCESS
    ALLOWED_NETWORK_RULES = (FLUX_EXTERNAL_ACCESS_RULE)
    ENABLED = TRUE
    COMMENT = 'External access integration for Flux SPCS services';

-- -----------------------------------------------------------------------------
-- 4. CREATE SECRETS FOR SERVICE CONFIGURATION
-- -----------------------------------------------------------------------------

-- Create secrets schema if not exists
CREATE SCHEMA IF NOT EXISTS SECRETS;

-- Application secrets (values would be set during deployment)
CREATE SECRET IF NOT EXISTS SECRETS.FLUX_APP_CONFIG
    TYPE = GENERIC_STRING
    SECRET_STRING = '{"app_name": "Flux Operations Center", "version": "2.0.0"}'
    COMMENT = 'Flux application configuration';

-- -----------------------------------------------------------------------------
-- 5. CREATE STAGES FOR SERVICE SPECS
-- -----------------------------------------------------------------------------

CREATE STAGE IF NOT EXISTS APPLICATIONS.SPCS_SPECS
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for SPCS service specification files';

-- -----------------------------------------------------------------------------
-- 6. CREATE FLUX OPS CENTER SERVICE
-- -----------------------------------------------------------------------------
-- Note: This creates the service from inline specification
-- Production deployments should use EXECUTE IMMEDIATE FROM for version control

CREATE SERVICE IF NOT EXISTS APPLICATIONS.IDENTIFIER('<% spcs_service %>')
    IN COMPUTE POOL IDENTIFIER('<% compute_pool %>')
    MIN_INSTANCES = 1
    MAX_INSTANCES = 3
    AUTO_RESUME = TRUE
    EXTERNAL_ACCESS_INTEGRATIONS = (FLUX_EXTERNAL_ACCESS)
    COMMENT = 'Flux Operations Center - Main application service'
    SPEC = $$
spec:
  containers:
    - name: flux-ops-center
      image: /<% database %>/APPLICATIONS/FLUX_IMAGES/flux-ops-center:latest
      env:
        SNOWFLAKE_DATABASE: <% database %>
        SNOWFLAKE_SCHEMA: PRODUCTION
        SNOWFLAKE_WAREHOUSE: <% warehouse %>
        APP_NAME: Flux Operations Center
        APP_VERSION: 2.0.0
        LOG_LEVEL: INFO
      resources:
        requests:
          memory: 2Gi
          cpu: 1
        limits:
          memory: 4Gi
          cpu: 2
      ports:
        - name: http
          port: 8501
          public: true
      readinessProbe:
        httpGet:
          path: /_stcore/health
          port: 8501
        initialDelaySeconds: 10
        periodSeconds: 5
      livenessProbe:
        httpGet:
          path: /_stcore/health
          port: 8501
        initialDelaySeconds: 30
        periodSeconds: 10
      volumeMounts:
        - name: data-volume
          mountPath: /app/data
  volumes:
    - name: data-volume
      source: "@<% database %>.APPLICATIONS.SPCS_SPECS"
  endpoints:
    - name: flux-ui
      port: 8501
      public: true
$$;

-- -----------------------------------------------------------------------------
-- 7. CREATE DATA FORGE SERVICE
-- -----------------------------------------------------------------------------
-- Service for data generation and ETL operations

CREATE SERVICE IF NOT EXISTS APPLICATIONS.FLUX_DATA_FORGE_SERVICE
    IN COMPUTE POOL IDENTIFIER('<% compute_pool %>')
    MIN_INSTANCES = 0
    MAX_INSTANCES = 2
    AUTO_RESUME = TRUE
    COMMENT = 'Flux Data Forge - Data generation and ETL service'
    SPEC = $$
spec:
  containers:
    - name: data-forge
      image: /<% database %>/APPLICATIONS/FLUX_IMAGES/flux-data-forge:latest
      env:
        SNOWFLAKE_DATABASE: <% database %>
        SNOWFLAKE_SCHEMA: PRODUCTION
        MODE: BATCH
      resources:
        requests:
          memory: 1Gi
          cpu: 0.5
        limits:
          memory: 2Gi
          cpu: 1
      ports:
        - name: http
          port: 8080
  endpoints:
    - name: api
      port: 8080
$$;

-- -----------------------------------------------------------------------------
-- 8. SERVICE STATUS AND ENDPOINTS
-- -----------------------------------------------------------------------------

-- Show services
SHOW SERVICES IN SCHEMA APPLICATIONS;

-- Get service endpoints (run after services start)
-- CALL SYSTEM$GET_SERVICE_STATUS('APPLICATIONS.<% spcs_service %>');
-- SELECT SYSTEM$GET_SERVICE_ENDPOINT('APPLICATIONS.<% spcs_service %>', 'flux-ui');

-- -----------------------------------------------------------------------------
-- 9. GRANTS
-- -----------------------------------------------------------------------------

GRANT USAGE ON SERVICE APPLICATIONS.IDENTIFIER('<% spcs_service %>') 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT USAGE ON SERVICE APPLICATIONS.FLUX_DATA_FORGE_SERVICE 
    TO ROLE IDENTIFIER('<% admin_role %>');

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 14_geospatial_functions.sql for geospatial capabilities
-- =============================================================================
