-- ============================================================================
-- Deploy Flux Utility Solutions from Git
-- ============================================================================
-- This script deploys the complete Flux ecosystem using EXECUTE IMMEDIATE FROM.
-- Run after setup_git_integration.sql has been completed.
--
-- Usage:
--   EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/git_deploy/deploy_from_git.sql
--     USING (
--       database => 'FLUX_PROD',
--       warehouse => 'FLUX_WH',
--       admin_role => 'ACCOUNTADMIN',
--       user_role => 'FLUX_USER'
--     );
-- ============================================================================

-- Declare parameters with defaults
SET database = COALESCE($database, 'FLUX_PROD');
SET warehouse = COALESCE($warehouse, 'FLUX_WH');
SET admin_role = COALESCE($admin_role, 'ACCOUNTADMIN');
SET user_role = COALESCE($user_role, 'PUBLIC');

-- Log start
SELECT 'Starting Flux deployment to ' || $database AS deployment_info;

-- ============================================================================
-- Phase 1: Infrastructure Setup
-- ============================================================================

SELECT '=== Phase 1: Infrastructure Setup ===' AS phase;

-- Fetch latest from git
ALTER GIT REPOSITORY flux_utility_solutions_repo FETCH;

-- Execute infrastructure script - creates database, schemas, roles
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/01_database_infrastructure.sql
  USING (database => $database, warehouse => $warehouse, admin_role => $admin_role, user_role => $user_role);

-- Execute warehouse setup
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/02_warehouses.sql
  USING (database => $database, warehouse => $warehouse, admin_role => $admin_role);

SELECT 'Phase 1 complete: Database, schemas, and warehouses created' AS status;

-- ============================================================================
-- Phase 2: Grid Foundation Tables
-- ============================================================================

SELECT '=== Phase 2: Grid Foundation ===' AS phase;

-- Substations and Transformers
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/03_substations_transformers.sql
  USING (database => $database);

-- Meters infrastructure
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/04_meters_infrastructure.sql
  USING (database => $database);

-- Customer master data
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/05_customers_master.sql
  USING (database => $database);

SELECT 'Phase 2 complete: Grid foundation tables created' AS status;

-- ============================================================================
-- Phase 3: AMI and Operational Data
-- ============================================================================

SELECT '=== Phase 3: AMI and Operational Data ===' AS phase;

-- AMI readings pipeline
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/06_ami_readings_pipeline.sql
  USING (database => $database, warehouse => $warehouse);

-- Aggregation tables (hourly load, outages, voltage sags)
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/07_aggregation_tables.sql
  USING (database => $database);

SELECT 'Phase 3 complete: AMI and aggregation tables created' AS status;

-- ============================================================================
-- Phase 4: Cortex AI Layer
-- ============================================================================

SELECT '=== Phase 4: Cortex AI Setup ===' AS phase;

-- Semantic View for Cortex Analyst
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/08_semantic_view.sql
  USING (database => $database);

-- Cortex Search Services
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/09_cortex_search_services.sql
  USING (database => $database, warehouse => $warehouse);

-- Cortex Agent
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/10_cortex_agent.sql
  USING (database => $database);

SELECT 'Phase 4 complete: Cortex AI services configured' AS status;

-- ============================================================================
-- Phase 5: Streamlit Applications
-- ============================================================================

SELECT '=== Phase 5: Streamlit Applications ===' AS phase;

-- Setup Streamlit stage
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/24_streamlit_stage_setup.sql
  USING (database => $database);

-- Note: Streamlit app files need to be uploaded to the stage before deploying apps
-- For Git Integration deployment, files are copied from the repo to the stage
BEGIN
    -- Copy Streamlit files from Git repo to stage
    COPY FILES INTO @IDENTIFIER($database || '.APPLICATIONS.STREAMLIT_STAGE')
    FROM @flux_utility_solutions_repo/branches/main/streamlit/
    PATTERN = '.*[.]py';
    
    COPY FILES INTO @IDENTIFIER($database || '.APPLICATIONS.STREAMLIT_STAGE/geospatial')
    FROM @flux_utility_solutions_repo/branches/main/streamlit/geospatial/;
    
    -- Deploy Streamlit apps
    EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/25_streamlit_apps.sql
      USING (database => $database, warehouse => $warehouse);
    
    SELECT 'Phase 5 complete: Streamlit apps deployed' AS status;
EXCEPTION
    WHEN OTHER THEN
        SELECT 'Streamlit deployment skipped - can be deployed manually using scripts/25_streamlit_apps.sql' AS status;
END;

-- ============================================================================
-- Phase 6: Notebooks Deployment
-- ============================================================================

SELECT '=== Phase 6: Notebooks ===' AS phase;

BEGIN
    -- Setup notebooks stage
    EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/26_notebooks_deployment.sql
      USING (database => $database);
    
    -- Copy notebook files from Git repo to stage
    COPY FILES INTO @IDENTIFIER($database || '.APPLICATIONS.NOTEBOOKS_STAGE/setup')
    FROM @flux_utility_solutions_repo/branches/main/notebooks/setup/;
    
    COPY FILES INTO @IDENTIFIER($database || '.APPLICATIONS.NOTEBOOKS_STAGE/demos')
    FROM @flux_utility_solutions_repo/branches/main/notebooks/demos/;
    
    COPY FILES INTO @IDENTIFIER($database || '.APPLICATIONS.NOTEBOOKS_STAGE/advanced')
    FROM @flux_utility_solutions_repo/branches/main/notebooks/advanced/;
    
    SELECT 'Phase 6 complete: Notebooks deployed to stage' AS status;
EXCEPTION
    WHEN OTHER THEN
        SELECT 'Notebooks deployment skipped - can be deployed manually using scripts/26_notebooks_deployment.sql' AS status;
END;

-- ============================================================================
-- Phase 7: ML and Advanced Features (Optional)
-- ============================================================================

SELECT '=== Phase 7: ML Features ===' AS phase;

-- ML Feature tables
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/11_ml_feature_tables.sql
  USING (database => $database);

SELECT 'Phase 7 complete: ML feature tables created' AS status;

-- ============================================================================
-- Phase 7b: Flux Ops Center SPCS Dependencies (Optional)
-- ============================================================================
-- Creates views and tables required by Flux Ops Center SPCS application
-- Skip this phase if not deploying Ops Center

SELECT '=== Phase 7b: Ops Center Dependencies ===' AS phase;

BEGIN
    EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/30_ops_center_dependencies.sql
      USING (database => $database, warehouse => $warehouse, admin_role => $admin_role, user_role => $user_role);
    SELECT 'Phase 7b complete: Ops Center dependencies created (APPLICATIONS views, ML_DEMO, CASCADE_ANALYSIS schemas)' AS status;
EXCEPTION
    WHEN OTHER THEN
        SELECT 'Ops Center dependencies skipped - can be deployed separately using scripts/30_ops_center_dependencies.sql' AS status;
END;

-- ============================================================================
-- Phase 8: Security and RBAC
-- ============================================================================

SELECT '=== Phase 8: Security Setup ===' AS phase;

-- Final RBAC grants
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/16_rbac_final.sql
  USING (database => $database, admin_role => $admin_role, user_role => $user_role, warehouse => $warehouse);

SELECT 'Phase 8 complete: RBAC configured' AS status;

-- ============================================================================
-- Phase 9: Seed Data Loading
-- ============================================================================

SELECT '=== Phase 9: Seed Data Loading ===' AS phase;

-- Load seed data from source database (if configured)
-- This copies reference tables and generates sample AMI data
BEGIN
    EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/50_load_seed_data.sql
      USING (database => $database, warehouse => $warehouse);
    SELECT 'Seed data loaded from source' AS status;
EXCEPTION
    WHEN OTHER THEN
        SELECT 'Source database not accessible - tables created but empty. Load seed data manually.' AS status;
END;

-- Generate AMI sample data
BEGIN
    EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/51_generate_ami_sample.sql
      USING (database => $database, days => 7);
    SELECT 'AMI sample data generated (7 days)' AS status;
EXCEPTION
    WHEN OTHER THEN
        SELECT 'AMI generation skipped - can be run separately' AS status;
END;

SELECT 'Phase 9 complete: Seed data loaded' AS status;

-- ============================================================================
-- Phase 10: Validation
-- ============================================================================

SELECT '=== Phase 10: Validation ===' AS phase;

EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/99_validate_deployment.sql
  USING (database => $database);

-- ============================================================================
-- Deployment Complete
-- ============================================================================

SELECT 
  'Flux Utility Solutions deployed successfully!' AS message,
  $database AS database,
  CURRENT_TIMESTAMP() AS deployed_at;

-- Summary
SELECT 
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE CATALOG_NAME = $database) AS schemas_created,
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_CATALOG = $database AND TABLE_TYPE = 'BASE TABLE') AS tables_created,
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_CATALOG = $database) AS views_created,
  (SELECT SUM(ROW_COUNT) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_CATALOG = $database) AS total_rows;
