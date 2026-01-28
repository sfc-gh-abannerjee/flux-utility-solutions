-- =============================================================================
-- 19_git_integration.sql
-- Flux Utility Solutions - Git Repository Integration Setup
-- =============================================================================
-- Purpose: Configure Git integration for EXECUTE IMMEDIATE FROM deployment
-- Dependencies: 01_database_infrastructure.sql
-- Jinja2 Variables:
--   <% database %>     - Target database name
--   <% git_repo_url %> - Git repository URL
--   <% admin_role %>   - Admin role
--
-- Reference: https://docs.snowflake.com/en/developer-guide/git/git-overview
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE SCHEMA APPLICATIONS;

-- -----------------------------------------------------------------------------
-- 1. CREATE API INTEGRATION FOR GIT
-- -----------------------------------------------------------------------------
-- Required for accessing Git repositories

CREATE OR REPLACE API INTEGRATION FLUX_GIT_INTEGRATION
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/Snowflake-Labs/')
    ENABLED = TRUE
    COMMENT = 'Git integration for Flux utility solutions repository';

-- Grant usage to admin role
GRANT USAGE ON INTEGRATION FLUX_GIT_INTEGRATION TO ROLE IDENTIFIER('<% admin_role %>');

-- -----------------------------------------------------------------------------
-- 2. CREATE GIT REPOSITORY
-- -----------------------------------------------------------------------------

CREATE OR REPLACE GIT REPOSITORY FLUX_SOLUTIONS_REPO
    API_INTEGRATION = FLUX_GIT_INTEGRATION
    ORIGIN = 'https://github.com/Snowflake-Labs/flux-utility-solutions.git'
    COMMENT = 'Flux Utility Solutions Git repository';

-- Grant usage
GRANT READ ON GIT REPOSITORY FLUX_SOLUTIONS_REPO TO ROLE IDENTIFIER('<% admin_role %>');

-- -----------------------------------------------------------------------------
-- 3. FETCH LATEST FROM REPOSITORY
-- -----------------------------------------------------------------------------

-- Fetch latest commits
ALTER GIT REPOSITORY FLUX_SOLUTIONS_REPO FETCH;

-- Show available branches
SHOW GIT BRANCHES IN GIT REPOSITORY FLUX_SOLUTIONS_REPO;

-- Show files in repository
LS @FLUX_SOLUTIONS_REPO/branches/main/scripts/;

-- -----------------------------------------------------------------------------
-- 4. DEPLOYMENT FROM GIT PROCEDURE
-- -----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE EXECUTE_SCRIPT_FROM_GIT(
    P_SCRIPT_NAME VARCHAR,
    P_BRANCH VARCHAR DEFAULT 'main',
    P_CONFIG OBJECT DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Execute a single SQL script from Git repository with Jinja2 substitution'
AS
$$
DECLARE
    v_script_path VARCHAR;
    v_database VARCHAR;
    v_warehouse VARCHAR;
    v_admin_role VARCHAR;
    v_user_role VARCHAR;
BEGIN
    -- Build script path
    v_script_path := '@FLUX_SOLUTIONS_REPO/branches/' || :P_BRANCH || '/scripts/' || :P_SCRIPT_NAME;
    
    -- Get config values (from parameter or defaults)
    v_database := COALESCE(:P_CONFIG:database::VARCHAR, CURRENT_DATABASE());
    v_warehouse := COALESCE(:P_CONFIG:warehouse::VARCHAR, 'SI_DEMO_WH');
    v_admin_role := COALESCE(:P_CONFIG:admin_role::VARCHAR, 'ACCOUNTADMIN');
    v_user_role := COALESCE(:P_CONFIG:user_role::VARCHAR, 'PUBLIC');
    
    -- Execute script with Jinja2 variable substitution
    EXECUTE IMMEDIATE FROM :v_script_path
        USING (
            database => :v_database,
            warehouse => :v_warehouse,
            admin_role => :v_admin_role,
            user_role => :v_user_role
        );
    
    RETURN 'Successfully executed ' || :P_SCRIPT_NAME || ' from branch ' || :P_BRANCH;
EXCEPTION
    WHEN OTHER THEN
        RETURN 'Failed to execute ' || :P_SCRIPT_NAME || ': ' || SQLERRM;
END;
$$;

-- -----------------------------------------------------------------------------
-- 5. FULL DEPLOYMENT FROM GIT PROCEDURE
-- -----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE DEPLOY_ALL_FROM_GIT(
    P_BRANCH VARCHAR DEFAULT 'main',
    P_ENVIRONMENT VARCHAR DEFAULT 'dev',
    P_DRY_RUN BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
    SCRIPT_NAME VARCHAR,
    STATUS VARCHAR,
    MESSAGE VARCHAR
)
LANGUAGE SQL
COMMENT = 'Deploy all Flux scripts from Git repository'
AS
$$
DECLARE
    v_config OBJECT;
    v_scripts ARRAY;
    v_results ARRAY;
    v_script VARCHAR;
    v_status VARCHAR;
    v_message VARCHAR;
BEGIN
    -- Set config based on environment
    CASE :P_ENVIRONMENT
        WHEN 'prod' THEN
            v_config := OBJECT_CONSTRUCT(
                'database', 'FLUX_PROD',
                'warehouse', 'FLUX_PROD_WH',
                'admin_role', 'FLUX_PROD_ADMIN',
                'user_role', 'FLUX_PROD_USER'
            );
        WHEN 'staging' THEN
            v_config := OBJECT_CONSTRUCT(
                'database', 'FLUX_STAGING',
                'warehouse', 'FLUX_STAGING_WH',
                'admin_role', 'FLUX_STAGING_ADMIN',
                'user_role', 'FLUX_STAGING_USER'
            );
        ELSE -- dev
            v_config := OBJECT_CONSTRUCT(
                'database', 'FLUX_DEV',
                'warehouse', 'SI_DEMO_WH',
                'admin_role', 'ACCOUNTADMIN',
                'user_role', 'PUBLIC'
            );
    END CASE;
    
    -- Script execution order
    v_scripts := ARRAY_CONSTRUCT(
        '01_database_infrastructure.sql',
        '02_warehouses.sql',
        '03_substations_transformers.sql',
        '04_meters_infrastructure.sql',
        '05_customers_master.sql',
        '06_ami_readings_pipeline.sql',
        '07_aggregation_tables.sql',
        '08_semantic_view.sql',
        '09_cortex_search_services.sql',
        '10_cortex_agent.sql',
        '11_ml_feature_tables.sql',
        '14_geospatial_functions.sql',
        '16_rbac_final.sql',
        '17_validation_queries.sql'
    );
    
    v_results := ARRAY_CONSTRUCT();
    
    -- Execute each script
    FOR i IN 0 TO ARRAY_SIZE(:v_scripts) - 1 DO
        v_script := :v_scripts[i]::VARCHAR;
        
        IF (:P_DRY_RUN) THEN
            v_status := 'DRY_RUN';
            v_message := 'Would execute: @FLUX_SOLUTIONS_REPO/branches/' || :P_BRANCH || '/scripts/' || :v_script;
        ELSE
            BEGIN
                CALL EXECUTE_SCRIPT_FROM_GIT(:v_script, :P_BRANCH, :v_config);
                v_status := 'SUCCESS';
                v_message := 'Executed successfully';
            EXCEPTION
                WHEN OTHER THEN
                    v_status := 'FAILED';
                    v_message := SQLERRM;
            END;
        END IF;
        
        v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT(
            'SCRIPT_NAME', :v_script,
            'STATUS', :v_status,
            'MESSAGE', :v_message
        ));
    END FOR;
    
    RETURN TABLE(
        SELECT 
            VALUE:SCRIPT_NAME::VARCHAR AS SCRIPT_NAME,
            VALUE:STATUS::VARCHAR AS STATUS,
            VALUE:MESSAGE::VARCHAR AS MESSAGE
        FROM TABLE(FLATTEN(INPUT => :v_results))
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- 6. VERIFICATION
-- -----------------------------------------------------------------------------

-- Show Git repository
SHOW GIT REPOSITORIES IN SCHEMA APPLICATIONS;

-- List scripts in repo
LS @FLUX_SOLUTIONS_REPO/branches/main/scripts/ PATTERN = '.*\\.sql';

-- Test dry run deployment
-- CALL DEPLOY_ALL_FROM_GIT('main', 'dev', TRUE);

-- Show available procedures
SHOW PROCEDURES LIKE '%GIT%' IN SCHEMA APPLICATIONS;

-- =============================================================================
-- GIT INTEGRATION COMPLETE
--
-- Usage:
--   -- Fetch latest from Git
--   ALTER GIT REPOSITORY FLUX_SOLUTIONS_REPO FETCH;
--
--   -- Execute single script
--   CALL EXECUTE_SCRIPT_FROM_GIT('01_database_infrastructure.sql', 'main', 
--        OBJECT_CONSTRUCT('database', 'MY_DB'));
--
--   -- Full deployment (dry run)
--   CALL DEPLOY_ALL_FROM_GIT('main', 'dev', TRUE);
--
--   -- Full deployment (execute)
--   CALL DEPLOY_ALL_FROM_GIT('main', 'prod', FALSE);
--
-- =============================================================================
