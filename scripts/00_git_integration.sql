-- ============================================================================
-- Flux Utility Solutions - Git Repository Integration Setup
-- ============================================================================
-- Purpose: Connect this GitHub repository to Snowflake for GitOps deployment
-- 
-- This enables:
--   1. Direct COPY INTO from repository files
--   2. Notebook imports from Git
--   3. CI/CD integration for schema changes
--   4. Version-controlled seed data loading
--
-- Prerequisites:
--   - ACCOUNTADMIN role (or CREATE INTEGRATION privilege)
--   - GitHub repository URL and access token (for private repos)
-- ============================================================================

-- Configuration - UPDATE THESE VALUES
SET database_name = 'FLUX_DEMO';
SET schema_name = 'PRODUCTION';
SET git_repo_name = 'FLUX_REPO';
SET github_url = 'https://github.com/Snowflake-Labs/flux-utility-solutions.git';

-- For private repositories, create a secret first:
-- SET github_token = 'ghp_xxxxxxxxxxxx';

-- ============================================================================
-- PHASE 1: Create API Integration for GitHub
-- ============================================================================

-- Note: Only needed once per account for GitHub access
CREATE OR REPLACE API INTEGRATION git_api_integration
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/')
    ENABLED = TRUE
    COMMENT = 'API integration for GitHub repositories';

-- Verify integration
SHOW API INTEGRATIONS LIKE 'git_api_integration';

-- ============================================================================
-- PHASE 2: Create Database and Schema (if not exists)
-- ============================================================================

CREATE DATABASE IF NOT EXISTS IDENTIFIER($database_name);
USE DATABASE IDENTIFIER($database_name);

CREATE SCHEMA IF NOT EXISTS IDENTIFIER($schema_name);
USE SCHEMA IDENTIFIER($schema_name);

-- ============================================================================
-- PHASE 3: Create Secret for Private Repos (Optional)
-- ============================================================================

-- Uncomment for private repositories:
/*
CREATE OR REPLACE SECRET flux_github_secret
    TYPE = password
    USERNAME = 'git'
    PASSWORD = $github_token
    COMMENT = 'GitHub PAT for flux-utility-solutions private repo';
*/

-- ============================================================================
-- PHASE 4: Create Git Repository
-- ============================================================================

-- For PUBLIC repository:
CREATE OR REPLACE GIT REPOSITORY IDENTIFIER($git_repo_name)
    API_INTEGRATION = git_api_integration
    ORIGIN = $github_url
    COMMENT = 'Flux Utility Solutions - Production reference architecture';

-- For PRIVATE repository (uncomment and use instead):
/*
CREATE OR REPLACE GIT REPOSITORY IDENTIFIER($git_repo_name)
    API_INTEGRATION = git_api_integration
    GIT_CREDENTIALS = flux_github_secret
    ORIGIN = $github_url
    COMMENT = 'Flux Utility Solutions - Production reference architecture';
*/

-- ============================================================================
-- PHASE 5: Verify and Fetch
-- ============================================================================

-- Verify repository was created
SHOW GIT REPOSITORIES;

-- Fetch latest from remote
ALTER GIT REPOSITORY IDENTIFIER($git_repo_name) FETCH;

-- List branches
SHOW GIT BRANCHES IN GIT REPOSITORY IDENTIFIER($git_repo_name);

-- List files in seed_data directory
LIST @FLUX_DEMO.PRODUCTION.FLUX_REPO/branches/main/seed_data/parquet/;

-- ============================================================================
-- PHASE 6: Quick Verification - Load Sample Table
-- ============================================================================

-- Test loading substations from Git repo
CREATE TABLE IF NOT EXISTS SUBSTATIONS_TEST (
    SUBSTATION_ID VARCHAR,
    SUBSTATION_NAME VARCHAR,
    LATITUDE FLOAT,
    LONGITUDE FLOAT,
    CAPACITY_MW FLOAT,
    VOLTAGE_LEVEL_KV FLOAT,
    INSTALL_DATE DATE,
    STATUS VARCHAR,
    REGION VARCHAR
);

COPY INTO SUBSTATIONS_TEST
FROM @FLUX_DEMO.PRODUCTION.FLUX_REPO/branches/main/seed_data/parquet/reference/substations
FILE_FORMAT = (TYPE = PARQUET)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

SELECT COUNT(*) as row_count FROM SUBSTATIONS_TEST;
-- Expected: 275 rows

-- Cleanup test table
DROP TABLE IF EXISTS SUBSTATIONS_TEST;

-- ============================================================================
-- USAGE EXAMPLES
-- ============================================================================

/*
-- 1. Load all seed data using the notebook:
--    Import notebooks/setup/02_load_seed_data.ipynb into Snowsight

-- 2. Execute SQL scripts directly from repo:
EXECUTE IMMEDIATE FROM @FLUX_REPO/branches/main/scripts/01_database_infrastructure.sql;

-- 3. List available scripts:
LIST @FLUX_REPO/branches/main/scripts/ PATTERN='.*\.sql';

-- 4. List available notebooks:
LIST @FLUX_REPO/branches/main/notebooks/ PATTERN='.*\.ipynb';

-- 5. Update to latest version:
ALTER GIT REPOSITORY FLUX_REPO FETCH;

-- 6. Switch to a different branch:
-- Use @FLUX_REPO/branches/feature-branch/ instead of /branches/main/
*/

-- ============================================================================
-- SUCCESS MESSAGE
-- ============================================================================

SELECT 'Git Repository Integration Complete!' as status,
       $database_name || '.' || $schema_name || '.' || $git_repo_name as repository_path,
       'Run: notebooks/setup/02_load_seed_data.ipynb to load all seed data' as next_step;
