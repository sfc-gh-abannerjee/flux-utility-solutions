-- =============================================================================
-- Flux Utility Solutions - Infrastructure Deployment Notebook
-- =============================================================================
-- Deploy database, schemas, warehouses, and roles via Snowflake Notebook
-- Run in: Snowsight → Projects → Notebooks
-- Variables: Set {{ database }}, {{ warehouse }}, etc. before running
-- =============================================================================

-- ## 1. Introduction
-- 
-- This notebook deploys the Flux Utility Solutions infrastructure including:
-- - Database and schemas (PRODUCTION, APPLICATIONS, SECRETS)
-- - Warehouses (Primary, Large, Loading, Cortex)
-- - Roles and grants (Admin, User, Analyst, ETL)
-- 
-- **Prerequisites:**
-- - ACCOUNTADMIN or equivalent role
-- - Permission to create databases and warehouses

-- ## 2. Configuration
-- 
-- Set these variables before running:

SET database_name = 'FLUX_DEV';
SET admin_role = 'FLUX_DEV_ADMIN';
SET user_role = 'FLUX_DEV_USER';
SET warehouse_prefix = 'FLUX_DEV';

-- Verify settings
SELECT 
    $database_name AS DATABASE,
    $admin_role AS ADMIN_ROLE,
    $user_role AS USER_ROLE,
    $warehouse_prefix AS WAREHOUSE_PREFIX;

-- ## 3. Create Database
-- 
-- Create the main database with Time Travel enabled.

CREATE DATABASE IF NOT EXISTS IDENTIFIER($database_name)
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Flux Utility Solutions - Grid Analytics Platform';

-- Verify
SHOW DATABASES LIKE 'FLUX%';

-- ## 4. Create Schemas
-- 
-- Create three schemas:
-- - **PRODUCTION**: Core data tables
-- - **APPLICATIONS**: Semantic views, agents, services
-- - **SECRETS**: Sensitive configuration

USE DATABASE IDENTIFIER($database_name);

CREATE SCHEMA IF NOT EXISTS PRODUCTION
    COMMENT = 'Production data tables - AMI readings, transformers, customers';

CREATE SCHEMA IF NOT EXISTS APPLICATIONS
    COMMENT = 'Semantic views, Cortex agents, search services';

CREATE SCHEMA IF NOT EXISTS SECRETS
    COMMENT = 'Application secrets and sensitive configuration';

-- Verify
SHOW SCHEMAS IN DATABASE IDENTIFIER($database_name);

-- ## 5. Create Roles
-- 
-- Create role hierarchy:
-- - Admin → User → Analyst
-- - Admin → ETL
-- - Admin → Service

CREATE ROLE IF NOT EXISTS IDENTIFIER($admin_role)
    COMMENT = 'Flux Admin - Full database and service management';

CREATE ROLE IF NOT EXISTS IDENTIFIER($user_role)
    COMMENT = 'Flux User - Read access to data and execute agents';

CREATE ROLE IF NOT EXISTS FLUX_ANALYST_ROLE
    COMMENT = 'Flux Analyst - Cortex Analyst and semantic view access';

CREATE ROLE IF NOT EXISTS FLUX_ETL_ROLE
    COMMENT = 'Flux ETL - Data loading and pipeline management';

-- Role hierarchy
GRANT ROLE IDENTIFIER($user_role) TO ROLE IDENTIFIER($admin_role);
GRANT ROLE FLUX_ANALYST_ROLE TO ROLE IDENTIFIER($user_role);
GRANT ROLE FLUX_ETL_ROLE TO ROLE IDENTIFIER($admin_role);

-- Verify
SHOW ROLES LIKE 'FLUX%';

-- ## 6. Create Warehouses
-- 
-- Create four warehouses for different workloads:

-- Primary warehouse
CREATE WAREHOUSE IF NOT EXISTS IDENTIFIER($warehouse_prefix || '_WH')
    WAREHOUSE_SIZE = 'SMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    COMMENT = 'Primary warehouse for interactive queries';

-- Large warehouse for AMI queries
CREATE WAREHOUSE IF NOT EXISTS IDENTIFIER($warehouse_prefix || '_LARGE_WH')
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 120
    AUTO_RESUME = TRUE
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 2
    ENABLE_QUERY_ACCELERATION = TRUE
    COMMENT = 'Large warehouse for AMI analytics';

-- Loading warehouse for ETL
CREATE WAREHOUSE IF NOT EXISTS IDENTIFIER($warehouse_prefix || '_LOADING_WH')
    WAREHOUSE_SIZE = 'SMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    COMMENT = 'Loading warehouse for ETL operations';

-- Cortex warehouse for AI
CREATE WAREHOUSE IF NOT EXISTS IDENTIFIER($warehouse_prefix || '_CORTEX_WH')
    WAREHOUSE_SIZE = 'SMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    COMMENT = 'Cortex warehouse for AI operations';

-- Verify
SHOW WAREHOUSES LIKE 'FLUX%';

-- ## 7. Grant Permissions
-- 
-- Set up RBAC with future grants for new objects.

-- Database grants
GRANT OWNERSHIP ON DATABASE IDENTIFIER($database_name) 
    TO ROLE IDENTIFIER($admin_role) COPY CURRENT GRANTS;

GRANT USAGE ON DATABASE IDENTIFIER($database_name) 
    TO ROLE IDENTIFIER($user_role);

-- Schema grants
GRANT ALL PRIVILEGES ON ALL SCHEMAS IN DATABASE IDENTIFIER($database_name) 
    TO ROLE IDENTIFIER($admin_role);

GRANT USAGE ON SCHEMA PRODUCTION TO ROLE IDENTIFIER($user_role);
GRANT USAGE ON SCHEMA APPLICATIONS TO ROLE IDENTIFIER($user_role);

-- Future table grants
GRANT SELECT ON FUTURE TABLES IN SCHEMA PRODUCTION 
    TO ROLE IDENTIFIER($user_role);

GRANT SELECT ON FUTURE VIEWS IN SCHEMA PRODUCTION 
    TO ROLE IDENTIFIER($user_role);

GRANT SELECT ON FUTURE SEMANTIC VIEWS IN SCHEMA APPLICATIONS 
    TO ROLE IDENTIFIER($user_role);

-- Warehouse grants
GRANT USAGE ON WAREHOUSE IDENTIFIER($warehouse_prefix || '_WH') 
    TO ROLE IDENTIFIER($user_role);

GRANT OPERATE ON WAREHOUSE IDENTIFIER($warehouse_prefix || '_WH') 
    TO ROLE IDENTIFIER($admin_role);

-- ## 8. Verification
-- 
-- Verify the deployment was successful.

-- Check database
SELECT 
    DATABASE_NAME,
    CREATED,
    COMMENT
FROM INFORMATION_SCHEMA.DATABASES
WHERE DATABASE_NAME = $database_name;

-- Check schemas
SELECT 
    SCHEMA_NAME,
    CREATED,
    COMMENT
FROM INFORMATION_SCHEMA.SCHEMATA
WHERE CATALOG_NAME = $database_name;

-- Check warehouses
SELECT 
    NAME,
    SIZE,
    STATE,
    AUTO_SUSPEND,
    AUTO_RESUME
FROM INFORMATION_SCHEMA.WAREHOUSES
WHERE NAME LIKE $warehouse_prefix || '%';

-- ## 9. Summary
-- 
-- Infrastructure deployment complete! Next steps:
-- 1. Run `02_deploy_tables.sql` to create production tables
-- 2. Run `03_deploy_cortex.sql` to set up Cortex services
-- 3. Load data or copy from source database

SELECT 
    '✅ Infrastructure Deployed Successfully' AS STATUS,
    $database_name AS DATABASE,
    CURRENT_TIMESTAMP() AS DEPLOYED_AT;
