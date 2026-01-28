-- =============================================================================
-- 16_rbac_final.sql
-- Flux Utility Solutions - Complete Role-Based Access Control
-- =============================================================================
-- Purpose: Finalize RBAC with comprehensive grants and future grants
-- Dependencies: All previous scripts (01-15)
-- Jinja2 Variables:
--   <% database %>    - Target database name
--   <% admin_role %>  - Admin role
--   <% user_role %>   - User role
--   <% warehouse %>   - Primary warehouse
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');

-- -----------------------------------------------------------------------------
-- 1. ROLE HIERARCHY SETUP
-- -----------------------------------------------------------------------------
-- Create complete role hierarchy following Snowflake best practices

-- Admin role (full control)
CREATE ROLE IF NOT EXISTS IDENTIFIER('<% admin_role %>')
    COMMENT = 'Flux Admin - Full database and service management';

-- User role (read access + execute)
CREATE ROLE IF NOT EXISTS IDENTIFIER('<% user_role %>')
    COMMENT = 'Flux User - Read access to data and execute agents';

-- Analyst role (read + semantic view access)
CREATE ROLE IF NOT EXISTS FLUX_ANALYST_ROLE
    COMMENT = 'Flux Analyst - Cortex Analyst and semantic view access';

-- ETL role (write access to staging tables)
CREATE ROLE IF NOT EXISTS FLUX_ETL_ROLE
    COMMENT = 'Flux ETL - Data loading and pipeline management';

-- Service role (for SPCS services)
CREATE ROLE IF NOT EXISTS FLUX_SERVICE_ROLE
    COMMENT = 'Flux Service - Service account for SPCS applications';

-- Grant role hierarchy
GRANT ROLE IDENTIFIER('<% user_role %>') TO ROLE IDENTIFIER('<% admin_role %>');
GRANT ROLE FLUX_ANALYST_ROLE TO ROLE IDENTIFIER('<% user_role %>');
GRANT ROLE FLUX_ETL_ROLE TO ROLE IDENTIFIER('<% admin_role %>');
GRANT ROLE FLUX_SERVICE_ROLE TO ROLE IDENTIFIER('<% admin_role %>');

-- -----------------------------------------------------------------------------
-- 2. DATABASE AND SCHEMA GRANTS
-- -----------------------------------------------------------------------------

-- Admin: Full database control
GRANT OWNERSHIP ON DATABASE IDENTIFIER('<% database %>') 
    TO ROLE IDENTIFIER('<% admin_role %>') COPY CURRENT GRANTS;

GRANT ALL PRIVILEGES ON ALL SCHEMAS IN DATABASE IDENTIFIER('<% database %>') 
    TO ROLE IDENTIFIER('<% admin_role %>');

-- User: Usage on database and schemas
GRANT USAGE ON DATABASE IDENTIFIER('<% database %>') 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT USAGE ON SCHEMA PRODUCTION TO ROLE IDENTIFIER('<% user_role %>');
GRANT USAGE ON SCHEMA APPLICATIONS TO ROLE IDENTIFIER('<% user_role %>');

-- Analyst: Same as user
GRANT USAGE ON DATABASE IDENTIFIER('<% database %>') 
    TO ROLE FLUX_ANALYST_ROLE;

GRANT USAGE ON SCHEMA APPLICATIONS TO ROLE FLUX_ANALYST_ROLE;

-- ETL: Production schema write access
GRANT USAGE ON DATABASE IDENTIFIER('<% database %>') 
    TO ROLE FLUX_ETL_ROLE;

GRANT ALL PRIVILEGES ON SCHEMA PRODUCTION TO ROLE FLUX_ETL_ROLE;

-- -----------------------------------------------------------------------------
-- 3. TABLE GRANTS
-- -----------------------------------------------------------------------------

-- User role: Read access to all production tables
GRANT SELECT ON ALL TABLES IN SCHEMA PRODUCTION 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT SELECT ON ALL VIEWS IN SCHEMA PRODUCTION 
    TO ROLE IDENTIFIER('<% user_role %>');

-- Future grants for user role
GRANT SELECT ON FUTURE TABLES IN SCHEMA PRODUCTION 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT SELECT ON FUTURE VIEWS IN SCHEMA PRODUCTION 
    TO ROLE IDENTIFIER('<% user_role %>');

-- Admin role: Full table control
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA PRODUCTION 
    TO ROLE IDENTIFIER('<% admin_role %>');

GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA PRODUCTION 
    TO ROLE IDENTIFIER('<% admin_role %>');

-- ETL role: Insert/Update/Delete on staging tables
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA PRODUCTION 
    TO ROLE FLUX_ETL_ROLE;

GRANT INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA PRODUCTION 
    TO ROLE FLUX_ETL_ROLE;

-- -----------------------------------------------------------------------------
-- 4. SEMANTIC VIEW GRANTS (Owner's Rights)
-- -----------------------------------------------------------------------------
-- Critical: Semantic views use owner's rights - grant SELECT carefully

GRANT SELECT ON ALL SEMANTIC VIEWS IN SCHEMA APPLICATIONS 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT SELECT ON FUTURE SEMANTIC VIEWS IN SCHEMA APPLICATIONS 
    TO ROLE IDENTIFIER('<% user_role %>');

-- Analyst role: Semantic view access
GRANT SELECT ON ALL SEMANTIC VIEWS IN SCHEMA APPLICATIONS 
    TO ROLE FLUX_ANALYST_ROLE;

GRANT SELECT ON FUTURE SEMANTIC VIEWS IN SCHEMA APPLICATIONS 
    TO ROLE FLUX_ANALYST_ROLE;

-- -----------------------------------------------------------------------------
-- 5. CORTEX SEARCH SERVICE GRANTS
-- -----------------------------------------------------------------------------

GRANT USAGE ON ALL CORTEX SEARCH SERVICES IN SCHEMA APPLICATIONS 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT USAGE ON FUTURE CORTEX SEARCH SERVICES IN SCHEMA APPLICATIONS 
    TO ROLE IDENTIFIER('<% user_role %>');

-- Analyst role
GRANT USAGE ON ALL CORTEX SEARCH SERVICES IN SCHEMA APPLICATIONS 
    TO ROLE FLUX_ANALYST_ROLE;

-- -----------------------------------------------------------------------------
-- 6. CORTEX AGENT GRANTS
-- -----------------------------------------------------------------------------

GRANT USAGE ON ALL AGENTS IN SCHEMA APPLICATIONS 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT USAGE ON FUTURE AGENTS IN SCHEMA APPLICATIONS 
    TO ROLE IDENTIFIER('<% user_role %>');

-- -----------------------------------------------------------------------------
-- 7. WAREHOUSE GRANTS
-- -----------------------------------------------------------------------------

-- Primary warehouse access
GRANT USAGE ON WAREHOUSE IDENTIFIER('<% warehouse %>') 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT USAGE ON WAREHOUSE IDENTIFIER('<% warehouse %>') 
    TO ROLE FLUX_ANALYST_ROLE;

GRANT USAGE ON WAREHOUSE IDENTIFIER('<% warehouse %>') 
    TO ROLE FLUX_ETL_ROLE;

GRANT OPERATE ON WAREHOUSE IDENTIFIER('<% warehouse %>') 
    TO ROLE IDENTIFIER('<% admin_role %>');

-- Large warehouse for admins only
GRANT USAGE ON WAREHOUSE IDENTIFIER('<% warehouse_ %>LARGE') 
    TO ROLE IDENTIFIER('<% admin_role %>');

GRANT OPERATE ON WAREHOUSE IDENTIFIER('<% warehouse_ %>LARGE') 
    TO ROLE IDENTIFIER('<% admin_role %>');

-- -----------------------------------------------------------------------------
-- 8. PROCEDURE AND FUNCTION GRANTS
-- -----------------------------------------------------------------------------

-- User role: Execute specific procedures
GRANT USAGE ON ALL PROCEDURES IN SCHEMA PRODUCTION 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT USAGE ON ALL FUNCTIONS IN SCHEMA PRODUCTION 
    TO ROLE IDENTIFIER('<% user_role %>');

-- Admin: Full procedure control
GRANT ALL PRIVILEGES ON ALL PROCEDURES IN SCHEMA PRODUCTION 
    TO ROLE IDENTIFIER('<% admin_role %>');

GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA PRODUCTION 
    TO ROLE IDENTIFIER('<% admin_role %>');

-- Future grants
GRANT USAGE ON FUTURE PROCEDURES IN SCHEMA PRODUCTION 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT USAGE ON FUTURE FUNCTIONS IN SCHEMA PRODUCTION 
    TO ROLE IDENTIFIER('<% user_role %>');

-- -----------------------------------------------------------------------------
-- 9. SPCS SERVICE GRANTS
-- -----------------------------------------------------------------------------

-- User role: Access to main application service
GRANT USAGE ON SERVICE APPLICATIONS.<% spcs_service %> 
    TO ROLE IDENTIFIER('<% user_role %>');

-- Admin: Full service control
GRANT ALL PRIVILEGES ON ALL SERVICES IN SCHEMA APPLICATIONS 
    TO ROLE IDENTIFIER('<% admin_role %>');

-- Service role: For service account operations
GRANT USAGE ON ALL SERVICES IN SCHEMA APPLICATIONS 
    TO ROLE FLUX_SERVICE_ROLE;

-- -----------------------------------------------------------------------------
-- 10. COMPUTE POOL GRANTS
-- -----------------------------------------------------------------------------

GRANT USAGE ON COMPUTE POOL IDENTIFIER('<% compute_pool %>') 
    TO ROLE IDENTIFIER('<% admin_role %>');

GRANT USAGE ON COMPUTE POOL FLUX_ML_POOL 
    TO ROLE IDENTIFIER('<% admin_role %>');

-- -----------------------------------------------------------------------------
-- 11. STAGE GRANTS
-- -----------------------------------------------------------------------------

GRANT READ, WRITE ON ALL STAGES IN SCHEMA APPLICATIONS 
    TO ROLE IDENTIFIER('<% admin_role %>');

GRANT READ ON ALL STAGES IN SCHEMA APPLICATIONS 
    TO ROLE IDENTIFIER('<% user_role %>');

-- -----------------------------------------------------------------------------
-- 12. VERIFICATION QUERIES
-- -----------------------------------------------------------------------------

-- Show role grants
SHOW GRANTS TO ROLE IDENTIFIER('<% admin_role %>');
SHOW GRANTS TO ROLE IDENTIFIER('<% user_role %>');
SHOW GRANTS TO ROLE FLUX_ANALYST_ROLE;

-- Verify future grants
SHOW FUTURE GRANTS IN SCHEMA PRODUCTION;
SHOW FUTURE GRANTS IN SCHEMA APPLICATIONS;

-- Summary of grants by role
SELECT 
    'RBAC Configuration Complete' AS STATUS,
    5 AS ROLE_COUNT,
    CURRENT_DATABASE() AS DATABASE_NAME,
    CURRENT_TIMESTAMP() AS CONFIGURED_AT;

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 17_validation_queries.sql to validate deployment
-- =============================================================================
