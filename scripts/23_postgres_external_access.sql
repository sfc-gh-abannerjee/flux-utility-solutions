-- =============================================================================
-- 23_postgres_external_access.sql
-- Flux Utility Solutions - PostgreSQL External Access Integration
-- =============================================================================
-- Purpose: Create secrets, network rules, and external access integration 
--          for connecting to managed PostgreSQL from SPCS services
-- Dependencies: 12_postgres_instance.sql (Managed PostgreSQL)
-- Jinja2 Variables:
--   {{ database }}        - Target database name
--   {{ postgres_host }}   - PostgreSQL host (or SPCS DNS endpoint)
--   {{ admin_role }}      - Admin role for grants
--   {{ user_role }}       - User role for grants
-- =============================================================================

USE DATABASE IDENTIFIER('{{ database }}');
USE SCHEMA PRODUCTION;

-- -----------------------------------------------------------------------------
-- 1. SECRET: PostgreSQL Credentials
-- -----------------------------------------------------------------------------
-- Store PostgreSQL credentials securely for use by SPCS services
-- Note: In SPCS, authentication uses OAuth/Snowflake identity, but for
-- external PostgreSQL connections, we need explicit credentials

CREATE OR ALTER SECRET APPLICATIONS.FLUX_POSTGRES_SECRET
    TYPE = PASSWORD
    USERNAME = 'postgres'
    PASSWORD = '{{ postgres_password }}'  -- Replace with actual password or use secrets manager
    COMMENT = 'PostgreSQL credentials for Flux Operations Center';

-- Generic secret for connection string format
CREATE OR ALTER SECRET APPLICATIONS.FLUX_POSTGRES_CONNECTION_SECRET
    TYPE = GENERIC_STRING
    SECRET_STRING = 'postgresql://postgres:{{ postgres_password }}@{{ postgres_host }}:5432/flux_operations'
    COMMENT = 'PostgreSQL connection string for FastAPI backend';


-- -----------------------------------------------------------------------------
-- 2. NETWORK RULE: PostgreSQL Access
-- -----------------------------------------------------------------------------
-- Allow SPCS services to connect to managed PostgreSQL instance

-- For SPCS-managed PostgreSQL (internal DNS)
CREATE OR ALTER NETWORK RULE APPLICATIONS.FLUX_POSTGRES_NETWORK_RULE
    TYPE = HOST_PORT
    MODE = EGRESS
    VALUE_LIST = (
        '{{ postgres_host }}:5432',
        'flux-operations-postgres.oybz.svc.spcs.internal:5432',  -- SPCS internal DNS
        'flux-operations-postgres.i3hf.svc.spcs.internal:5432'   -- Alternate region
    )
    COMMENT = 'Network rule for PostgreSQL connectivity from SPCS';

-- For Carto API access (geospatial visualization)
CREATE OR ALTER NETWORK RULE APPLICATIONS.FLUX_CARTO_NETWORK_RULE
    TYPE = HOST_PORT
    MODE = EGRESS
    VALUE_LIST = (
        'gcp-us-east1.api.carto.com:443',
        'api.carto.com:443'
    )
    COMMENT = 'Network rule for Carto API access';

-- For external APIs (weather, ERCOT, etc.)
CREATE OR ALTER NETWORK RULE APPLICATIONS.FLUX_EXTERNAL_API_RULE
    TYPE = HOST_PORT
    MODE = EGRESS
    VALUE_LIST = (
        'api.weather.gov:443',
        'www.ercot.com:443',
        'api.openstreetmap.org:443'
    )
    COMMENT = 'Network rule for external API access';


-- -----------------------------------------------------------------------------
-- 3. EXTERNAL ACCESS INTEGRATION: PostgreSQL
-- -----------------------------------------------------------------------------
-- Combine network rules and secrets into an integration for SPCS

CREATE OR ALTER EXTERNAL ACCESS INTEGRATION FLUX_POSTGRES_INTEGRATION
    ALLOWED_NETWORK_RULES = (
        APPLICATIONS.FLUX_POSTGRES_NETWORK_RULE
    )
    ALLOWED_AUTHENTICATION_SECRETS = (
        APPLICATIONS.FLUX_POSTGRES_SECRET,
        APPLICATIONS.FLUX_POSTGRES_CONNECTION_SECRET
    )
    ENABLED = TRUE
    COMMENT = 'External access for SPCS to connect to managed PostgreSQL';

-- Carto integration for map visualizations
CREATE OR ALTER EXTERNAL ACCESS INTEGRATION FLUX_CARTO_INTEGRATION
    ALLOWED_NETWORK_RULES = (
        APPLICATIONS.FLUX_CARTO_NETWORK_RULE
    )
    ENABLED = TRUE
    COMMENT = 'External access for Carto geospatial APIs';

-- External API integration
CREATE OR ALTER EXTERNAL ACCESS INTEGRATION FLUX_EXTERNAL_API_INTEGRATION
    ALLOWED_NETWORK_RULES = (
        APPLICATIONS.FLUX_EXTERNAL_API_RULE
    )
    ENABLED = TRUE
    COMMENT = 'External access for weather, ERCOT, and mapping APIs';


-- -----------------------------------------------------------------------------
-- 4. GRANTS: Allow Roles to Use Integrations
-- -----------------------------------------------------------------------------

-- Grant usage on secrets
GRANT USAGE ON SECRET APPLICATIONS.FLUX_POSTGRES_SECRET TO ROLE IDENTIFIER('{{ admin_role }}');
GRANT USAGE ON SECRET APPLICATIONS.FLUX_POSTGRES_CONNECTION_SECRET TO ROLE IDENTIFIER('{{ admin_role }}');

-- Grant usage on external access integrations
GRANT USAGE ON INTEGRATION FLUX_POSTGRES_INTEGRATION TO ROLE IDENTIFIER('{{ admin_role }}');
GRANT USAGE ON INTEGRATION FLUX_CARTO_INTEGRATION TO ROLE IDENTIFIER('{{ admin_role }}');
GRANT USAGE ON INTEGRATION FLUX_EXTERNAL_API_INTEGRATION TO ROLE IDENTIFIER('{{ admin_role }}');


-- -----------------------------------------------------------------------------
-- 5. VERIFICATION
-- -----------------------------------------------------------------------------

SHOW SECRETS IN SCHEMA APPLICATIONS;
SHOW NETWORK RULES IN SCHEMA APPLICATIONS;
SHOW EXTERNAL ACCESS INTEGRATIONS LIKE 'FLUX%';


-- =============================================================================
-- USAGE IN SPCS SERVICE SPEC
-- =============================================================================
-- Add these integrations to your service.yaml:
--
-- spec:
--   containers:
--     - name: flux-ops-center
--       ...
--       secrets:
--         - snowflakeSecret: APPLICATIONS.FLUX_POSTGRES_CONNECTION_SECRET
--           secretKeyRef: connectionString
--           envVarName: DATABASE_URL
--   serviceRoles:
--     - name: app-role
--       endpoints:
--         - app
--         - api
--   externalAccessIntegrations:
--     - FLUX_POSTGRES_INTEGRATION
--     - FLUX_CARTO_INTEGRATION
-- =============================================================================

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 24_postgres_sync_pipeline.sql to set up CDC streams and tasks
-- =============================================================================
