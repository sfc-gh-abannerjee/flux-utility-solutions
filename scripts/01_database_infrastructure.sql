-- =============================================================================
-- 01_database_infrastructure.sql
-- Flux Utility Solutions - Database and Schema Setup
-- =============================================================================
-- Purpose: Create database, schemas, roles, and grants for Flux deployment
-- Variables:
--   <% database %>    - Target database name (e.g., FLUX_PROD)
--   <% admin_role %>  - Administrator role
--   <% user_role %>   - End-user role for queries
-- 
-- Usage with Snow CLI:
--   snow sql -f scripts/01_database_infrastructure.sql \
--       -D "database=FLUX_PROD" -D "admin_role=FLUX_ADMIN" -D "user_role=FLUX_USER"
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. CREATE ROLES (if not exists)
-- -----------------------------------------------------------------------------
-- Note: Role creation requires USERADMIN or higher privileges

CREATE ROLE IF NOT EXISTS IDENTIFIER('<% admin_role %>')
    COMMENT = 'Flux Utility Solutions - Administrator role for deployment and management';

CREATE ROLE IF NOT EXISTS IDENTIFIER('<% user_role %>')
    COMMENT = 'Flux Utility Solutions - End-user role for queries and dashboards';

-- Grant user role to admin (role hierarchy)
GRANT ROLE IDENTIFIER('<% user_role %>') TO ROLE IDENTIFIER('<% admin_role %>');

-- -----------------------------------------------------------------------------
-- 2. CREATE DATABASE
-- -----------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS IDENTIFIER('<% database %>')
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Flux Utility Solutions - Production-grade utility grid analytics platform';

USE DATABASE IDENTIFIER('<% database %>');

-- -----------------------------------------------------------------------------
-- 3. CREATE SCHEMAS
-- -----------------------------------------------------------------------------
-- Following Snowflake best practices for data organization

-- PRODUCTION: Core operational data (tables, time-series)
CREATE SCHEMA IF NOT EXISTS PRODUCTION
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Production data - grid infrastructure, AMI readings, customer profiles';

-- APPLICATIONS: Application layer (views, semantic models, services)
CREATE SCHEMA IF NOT EXISTS APPLICATIONS
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Application objects - views, semantic views, Cortex services, SPCS';

-- RAW: Staging area for incoming data
CREATE SCHEMA IF NOT EXISTS RAW
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Raw/staging data - landing zone before transformation';

-- ML: Machine learning objects
CREATE SCHEMA IF NOT EXISTS ML
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'ML objects - feature tables, model registry, predictions';

-- ARCHIVE: Historical snapshots and backups
CREATE SCHEMA IF NOT EXISTS ARCHIVE
    DATA_RETENTION_TIME_IN_DAYS = 30
    COMMENT = 'Historical backups and archived data';

-- -----------------------------------------------------------------------------
-- 4. GRANT DATABASE PRIVILEGES
-- -----------------------------------------------------------------------------

-- Admin role gets full control
GRANT OWNERSHIP ON DATABASE IDENTIFIER('<% database %>') 
    TO ROLE IDENTIFIER('<% admin_role %>') COPY CURRENT GRANTS;

GRANT ALL PRIVILEGES ON DATABASE IDENTIFIER('<% database %>') 
    TO ROLE IDENTIFIER('<% admin_role %>');

-- User role gets usage
GRANT USAGE ON DATABASE IDENTIFIER('<% database %>') 
    TO ROLE IDENTIFIER('<% user_role %>');

-- -----------------------------------------------------------------------------
-- 5. GRANT SCHEMA PRIVILEGES
-- -----------------------------------------------------------------------------

-- Admin gets all schemas
GRANT ALL PRIVILEGES ON ALL SCHEMAS IN DATABASE IDENTIFIER('<% database %>') 
    TO ROLE IDENTIFIER('<% admin_role %>');

GRANT ALL PRIVILEGES ON FUTURE SCHEMAS IN DATABASE IDENTIFIER('<% database %>') 
    TO ROLE IDENTIFIER('<% admin_role %>');

-- User gets usage on PRODUCTION and APPLICATIONS
GRANT USAGE ON SCHEMA <% database %>.PRODUCTION 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT USAGE ON SCHEMA <% database %>.APPLICATIONS 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT USAGE ON SCHEMA <% database %>.ML 
    TO ROLE IDENTIFIER('<% user_role %>');

-- -----------------------------------------------------------------------------
-- 6. GRANT FUTURE OBJECT PRIVILEGES TO USER ROLE
-- -----------------------------------------------------------------------------
-- Following semantic view best practices from Snowflake documentation

-- Tables: SELECT for read access
GRANT SELECT ON FUTURE TABLES IN SCHEMA <% database %>.PRODUCTION 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT SELECT ON FUTURE TABLES IN SCHEMA <% database %>.APPLICATIONS 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT SELECT ON FUTURE TABLES IN SCHEMA <% database %>.ML 
    TO ROLE IDENTIFIER('<% user_role %>');

-- Views: SELECT for read access
GRANT SELECT ON FUTURE VIEWS IN SCHEMA <% database %>.PRODUCTION 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT SELECT ON FUTURE VIEWS IN SCHEMA <% database %>.APPLICATIONS 
    TO ROLE IDENTIFIER('<% user_role %>');

-- Semantic Views: SELECT (critical for Cortex Analyst)
GRANT SELECT ON FUTURE SEMANTIC VIEWS IN SCHEMA <% database %>.APPLICATIONS 
    TO ROLE IDENTIFIER('<% user_role %>');

-- Functions, Procedures, Stages: USAGE
GRANT USAGE ON FUTURE FUNCTIONS IN SCHEMA <% database %>.APPLICATIONS 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT USAGE ON FUTURE PROCEDURES IN SCHEMA <% database %>.APPLICATIONS 
    TO ROLE IDENTIFIER('<% user_role %>');

GRANT USAGE ON FUTURE STAGES IN SCHEMA <% database %>.APPLICATIONS 
    TO ROLE IDENTIFIER('<% user_role %>');

-- Cortex Search Services: USAGE (for RAG and search)
GRANT USAGE ON FUTURE CORTEX SEARCH SERVICES IN SCHEMA <% database %>.APPLICATIONS 
    TO ROLE IDENTIFIER('<% user_role %>');

-- -----------------------------------------------------------------------------
-- 7. CREATE INTERNAL STAGE FOR SEED DATA
-- -----------------------------------------------------------------------------

-- Grant ACCOUNTADMIN access to maintain administrative control
GRANT ALL PRIVILEGES ON DATABASE IDENTIFIER('<% database %>') TO ROLE ACCOUNTADMIN;

USE DATABASE IDENTIFIER('<% database %>');
USE SCHEMA RAW;

CREATE STAGE IF NOT EXISTS <% database %>.RAW.FLUX_SEED_DATA
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Internal stage for seed data files (parquet, CSV)';

GRANT READ ON STAGE <% database %>.RAW.FLUX_SEED_DATA TO ROLE IDENTIFIER('<% user_role %>');

-- -----------------------------------------------------------------------------
-- 8. VERIFICATION QUERIES
-- -----------------------------------------------------------------------------

-- Show created schemas
SHOW SCHEMAS IN DATABASE IDENTIFIER('<% database %>');

-- Verify grants
SHOW GRANTS ON DATABASE IDENTIFIER('<% database %>');

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 02_warehouses.sql to create compute warehouses
-- =============================================================================
