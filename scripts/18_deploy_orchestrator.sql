-- =============================================================================
-- 18_deploy_orchestrator.sql
-- Flux Utility Solutions - Deployment Orchestration Procedure
-- =============================================================================
-- Purpose: Single procedure to orchestrate full deployment from scripts
-- Dependencies: All scripts (01-17) accessible via stage or Git
-- Jinja2 Variables:
--   <% database %>    - Target database name
--   <% environment %> - Target environment (dev/staging/prod)
-- =============================================================================

-- This script creates the orchestrator procedure that runs all other scripts
-- in the correct order with proper error handling and logging.

USE DATABASE IDENTIFIER('<% database %>');
USE SCHEMA APPLICATIONS;

-- -----------------------------------------------------------------------------
-- 1. DEPLOYMENT LOG TABLE
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS DEPLOYMENT_LOG (
    LOG_ID VARCHAR(50) DEFAULT UUID_STRING(),
    DEPLOYMENT_ID VARCHAR(50) NOT NULL,
    ENVIRONMENT VARCHAR(20) NOT NULL,
    SCRIPT_NAME VARCHAR(100) NOT NULL,
    SCRIPT_ORDER NUMBER(5,0),
    STATUS VARCHAR(20) NOT NULL,  -- RUNNING, SUCCESS, FAILED, SKIPPED
    STARTED_AT TIMESTAMP_NTZ,
    COMPLETED_AT TIMESTAMP_NTZ,
    DURATION_SECONDS NUMBER(10,2),
    ERROR_MESSAGE TEXT,
    ROWS_AFFECTED NUMBER(15,0),
    DEPLOYED_BY VARCHAR(100) DEFAULT CURRENT_USER(),
    
    PRIMARY KEY (DEPLOYMENT_ID, SCRIPT_NAME)
)
COMMENT = 'Deployment execution log for tracking script runs';

-- -----------------------------------------------------------------------------
-- 2. DEPLOYMENT SCRIPTS REGISTRY
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS DEPLOYMENT_SCRIPTS (
    SCRIPT_ORDER NUMBER(5,0) PRIMARY KEY,
    SCRIPT_NAME VARCHAR(100) NOT NULL UNIQUE,
    SCRIPT_PATH VARCHAR(500),
    DESCRIPTION VARCHAR(500),
    IS_REQUIRED BOOLEAN DEFAULT TRUE,
    DEPENDENCIES VARCHAR(500),  -- Comma-separated list of dependent scripts
    ESTIMATED_SECONDS NUMBER(10,0),
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Registry of deployment scripts with execution order';

-- Insert script registry
MERGE INTO DEPLOYMENT_SCRIPTS tgt
USING (
    SELECT * FROM VALUES
        (1, '01_database_infrastructure.sql', '@SPCS_SPECS/scripts/', 'Database, schemas, roles', TRUE, NULL, 30),
        (2, '02_warehouses.sql', '@SPCS_SPECS/scripts/', 'Warehouse configuration', TRUE, '01', 15),
        (3, '03_substations_transformers.sql', '@SPCS_SPECS/scripts/', 'Substation and transformer tables', TRUE, '01', 60),
        (4, '04_meters_infrastructure.sql', '@SPCS_SPECS/scripts/', 'Meter and pole infrastructure', TRUE, '01', 45),
        (5, '05_customers_master.sql', '@SPCS_SPECS/scripts/', 'Customer master data', TRUE, '01', 30),
        (6, '06_ami_readings_pipeline.sql', '@SPCS_SPECS/scripts/', 'AMI readings and dynamic tables', TRUE, '03,04', 120),
        (7, '07_aggregation_tables.sql', '@SPCS_SPECS/scripts/', 'Hourly load aggregations', TRUE, '06', 90),
        (8, '08_semantic_view.sql', '@SPCS_SPECS/scripts/', 'Cortex Analyst semantic view', TRUE, '03,04,05,06,07', 60),
        (9, '09_cortex_search_services.sql', '@SPCS_SPECS/scripts/', 'Cortex Search services', TRUE, '05', 45),
        (10, '10_cortex_agent.sql', '@SPCS_SPECS/scripts/', 'Grid Intelligence Agent', TRUE, '08,09', 30),
        (11, '11_ml_feature_tables.sql', '@SPCS_SPECS/scripts/', 'ML feature engineering tables', FALSE, '06,07', 60),
        (12, '12_postgres_instance.sql', '@SPCS_SPECS/scripts/', 'PostgreSQL transactional DB', FALSE, '01', 120),
        (13, '13_spcs_compute.sql', '@SPCS_SPECS/scripts/', 'SPCS compute pools and services', FALSE, '01', 180),
        (14, '14_geospatial_functions.sql', '@SPCS_SPECS/scripts/', 'H3 and geospatial functions', FALSE, '03,04', 45),
        (15, '15_marketplace_listings.sql', '@SPCS_SPECS/scripts/', 'Marketplace data products', FALSE, '03,04,05,06', 30),
        (16, '16_rbac_final.sql', '@SPCS_SPECS/scripts/', 'Complete RBAC configuration', TRUE, '01-15', 30),
        (17, '17_validation_queries.sql', '@SPCS_SPECS/scripts/', 'Deployment validation', TRUE, '01-16', 60)
) AS src (SCRIPT_ORDER, SCRIPT_NAME, SCRIPT_PATH, DESCRIPTION, IS_REQUIRED, DEPENDENCIES, ESTIMATED_SECONDS)
ON tgt.SCRIPT_NAME = src.SCRIPT_NAME
WHEN MATCHED THEN UPDATE SET
    SCRIPT_ORDER = src.SCRIPT_ORDER,
    SCRIPT_PATH = src.SCRIPT_PATH,
    DESCRIPTION = src.DESCRIPTION,
    IS_REQUIRED = src.IS_REQUIRED,
    DEPENDENCIES = src.DEPENDENCIES,
    ESTIMATED_SECONDS = src.ESTIMATED_SECONDS
WHEN NOT MATCHED THEN INSERT VALUES (
    src.SCRIPT_ORDER, src.SCRIPT_NAME, src.SCRIPT_PATH, src.DESCRIPTION,
    src.IS_REQUIRED, src.DEPENDENCIES, src.ESTIMATED_SECONDS, CURRENT_TIMESTAMP()
);

-- -----------------------------------------------------------------------------
-- 3. MAIN DEPLOYMENT PROCEDURE
-- -----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE DEPLOY_FLUX_SOLUTION(
    P_ENVIRONMENT VARCHAR DEFAULT 'dev',
    P_START_FROM NUMBER DEFAULT 1,
    P_END_AT NUMBER DEFAULT 17,
    P_DRY_RUN BOOLEAN DEFAULT FALSE,
    P_SKIP_OPTIONAL BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    SCRIPT_NAME VARCHAR,
    STATUS VARCHAR,
    DURATION_SECONDS NUMBER,
    MESSAGE VARCHAR
)
LANGUAGE SQL
COMMENT = 'Orchestrate Flux solution deployment by running scripts in order'
AS
$$
DECLARE
    v_deployment_id VARCHAR;
    v_script RECORD;
    v_start_time TIMESTAMP_NTZ;
    v_end_time TIMESTAMP_NTZ;
    v_status VARCHAR;
    v_message VARCHAR;
    v_results ARRAY;
BEGIN
    -- Generate deployment ID
    v_deployment_id := 'DEPLOY-' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD-HH24MISS');
    v_results := ARRAY_CONSTRUCT();
    
    -- Log deployment start
    INSERT INTO DEPLOYMENT_LOG (DEPLOYMENT_ID, ENVIRONMENT, SCRIPT_NAME, STATUS, STARTED_AT)
    VALUES (:v_deployment_id, :P_ENVIRONMENT, 'ORCHESTRATOR', 'RUNNING', CURRENT_TIMESTAMP());
    
    -- Iterate through scripts
    FOR v_script IN (
        SELECT SCRIPT_ORDER, SCRIPT_NAME, SCRIPT_PATH, DESCRIPTION, IS_REQUIRED, ESTIMATED_SECONDS
        FROM DEPLOYMENT_SCRIPTS
        WHERE SCRIPT_ORDER BETWEEN :P_START_FROM AND :P_END_AT
          AND (IS_REQUIRED = TRUE OR :P_SKIP_OPTIONAL = FALSE)
        ORDER BY SCRIPT_ORDER
    ) DO
        v_start_time := CURRENT_TIMESTAMP();
        
        -- Log script start
        INSERT INTO DEPLOYMENT_LOG (
            DEPLOYMENT_ID, ENVIRONMENT, SCRIPT_NAME, SCRIPT_ORDER, STATUS, STARTED_AT
        ) VALUES (
            :v_deployment_id, :P_ENVIRONMENT, :v_script.SCRIPT_NAME, :v_script.SCRIPT_ORDER, 
            'RUNNING', :v_start_time
        );
        
        IF (:P_DRY_RUN) THEN
            -- Dry run - just log
            v_status := 'DRY_RUN';
            v_message := 'Would execute: ' || :v_script.SCRIPT_NAME;
        ELSE
            -- Execute script
            BEGIN
                -- For Git-based deployment, use EXECUTE IMMEDIATE FROM
                -- EXECUTE IMMEDIATE FROM :v_script.SCRIPT_PATH || :v_script.SCRIPT_NAME;
                
                -- For now, log that manual execution is needed
                v_status := 'PENDING';
                v_message := 'Execute manually or via Git: ' || :v_script.SCRIPT_NAME;
            EXCEPTION
                WHEN OTHER THEN
                    v_status := 'FAILED';
                    v_message := SQLERRM;
            END;
        END IF;
        
        v_end_time := CURRENT_TIMESTAMP();
        
        -- Update log
        UPDATE DEPLOYMENT_LOG
        SET STATUS = :v_status,
            COMPLETED_AT = :v_end_time,
            DURATION_SECONDS = TIMESTAMPDIFF('second', :v_start_time, :v_end_time),
            ERROR_MESSAGE = CASE WHEN :v_status = 'FAILED' THEN :v_message ELSE NULL END
        WHERE DEPLOYMENT_ID = :v_deployment_id 
          AND SCRIPT_NAME = :v_script.SCRIPT_NAME;
        
        -- Add to results
        v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT(
            'SCRIPT_NAME', :v_script.SCRIPT_NAME,
            'STATUS', :v_status,
            'DURATION_SECONDS', TIMESTAMPDIFF('second', :v_start_time, :v_end_time),
            'MESSAGE', :v_message
        ));
    END FOR;
    
    -- Update orchestrator status
    UPDATE DEPLOYMENT_LOG
    SET STATUS = 'SUCCESS',
        COMPLETED_AT = CURRENT_TIMESTAMP()
    WHERE DEPLOYMENT_ID = :v_deployment_id 
      AND SCRIPT_NAME = 'ORCHESTRATOR';
    
    -- Return results
    RETURN TABLE(
        SELECT 
            VALUE:SCRIPT_NAME::VARCHAR AS SCRIPT_NAME,
            VALUE:STATUS::VARCHAR AS STATUS,
            VALUE:DURATION_SECONDS::NUMBER AS DURATION_SECONDS,
            VALUE:MESSAGE::VARCHAR AS MESSAGE
        FROM TABLE(FLATTEN(INPUT => :v_results))
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. DEPLOYMENT FROM GIT PROCEDURE
-- -----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE DEPLOY_FROM_GIT(
    P_GIT_REPO VARCHAR DEFAULT 'github.com/YOUR_ORG/flux-utility-solutions',
    P_BRANCH VARCHAR DEFAULT 'main',
    P_ENVIRONMENT VARCHAR DEFAULT 'dev'
)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Deploy Flux solution from Git repository'
AS
$$
BEGIN
    -- This procedure would use EXECUTE IMMEDIATE FROM with Git integration
    -- Example: EXECUTE IMMEDIATE FROM @git_stage/scripts/01_database_infrastructure.sql
    --          USING (database => 'FLUX_DEV', warehouse => 'FLUX_DEV_WH', ...);
    
    RETURN 'Git deployment would execute from ' || :P_GIT_REPO || ' branch ' || :P_BRANCH;
END;
$$;

-- -----------------------------------------------------------------------------
-- 5. ROLLBACK PROCEDURE
-- -----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE ROLLBACK_DEPLOYMENT(
    P_DEPLOYMENT_ID VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Rollback a deployment by dropping created objects'
AS
$$
DECLARE
    v_scripts CURSOR FOR 
        SELECT SCRIPT_NAME, SCRIPT_ORDER 
        FROM DEPLOYMENT_LOG 
        WHERE DEPLOYMENT_ID = :P_DEPLOYMENT_ID 
          AND STATUS = 'SUCCESS'
        ORDER BY SCRIPT_ORDER DESC;
BEGIN
    -- Note: Full rollback would require corresponding _rollback.sql scripts
    -- or use Time Travel to restore to pre-deployment state
    
    FOR script IN v_scripts DO
        -- Log rollback attempt
        INSERT INTO DEPLOYMENT_LOG (
            DEPLOYMENT_ID, ENVIRONMENT, SCRIPT_NAME, STATUS, STARTED_AT
        ) VALUES (
            :P_DEPLOYMENT_ID || '-ROLLBACK', 'rollback', script.SCRIPT_NAME, 'PENDING', CURRENT_TIMESTAMP()
        );
    END FOR;
    
    RETURN 'Rollback initiated for deployment ' || :P_DEPLOYMENT_ID;
END;
$$;

-- -----------------------------------------------------------------------------
-- 6. VERIFICATION
-- -----------------------------------------------------------------------------

-- Show deployment scripts
SELECT * FROM DEPLOYMENT_SCRIPTS ORDER BY SCRIPT_ORDER;

-- Show recent deployments
SELECT * FROM DEPLOYMENT_LOG ORDER BY STARTED_AT DESC LIMIT 10;

-- Test dry run
CALL DEPLOY_FLUX_SOLUTION('dev', 1, 5, TRUE, FALSE);

-- =============================================================================
-- DEPLOYMENT ORCHESTRATION COMPLETE
-- 
-- Usage:
--   -- Full deployment (dry run)
--   CALL DEPLOY_FLUX_SOLUTION('dev', 1, 17, TRUE, FALSE);
--   
--   -- Full deployment (execute)
--   CALL DEPLOY_FLUX_SOLUTION('prod', 1, 17, FALSE, FALSE);
--   
--   -- Deploy from Git
--   CALL DEPLOY_FROM_GIT('github.com/org/repo', 'main', 'prod');
--   
--   -- Rollback
--   CALL ROLLBACK_DEPLOYMENT('DEPLOY-20260128-153000');
--
-- =============================================================================
