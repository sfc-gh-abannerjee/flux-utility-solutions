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
--       schema => 'PRODUCTION',
--       warehouse => 'FLUX_WH',
--       admin_role => 'ACCOUNTADMIN',
--       user_role => 'FLUX_USER'
--     );
-- ============================================================================

-- Declare parameters with defaults
SET database = COALESCE($database, 'FLUX_PROD');
SET schema_name = COALESCE($schema, 'PRODUCTION');
SET warehouse = COALESCE($warehouse, 'FLUX_WH');
SET admin_role = COALESCE($admin_role, 'ACCOUNTADMIN');
SET user_role = COALESCE($user_role, 'PUBLIC');

-- Log start
SELECT 'Starting Flux deployment to ' || $database || '.' || $schema_name AS deployment_info;

-- ============================================================================
-- Phase 1: Infrastructure Setup
-- ============================================================================

SELECT '=== Phase 1: Infrastructure Setup ===' AS phase;

-- Fetch latest from git
ALTER GIT REPOSITORY flux_utility_solutions_repo FETCH;

-- Execute infrastructure scripts
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/01_database_setup.sql
  USING (database => $database, warehouse => $warehouse, admin_role => $admin_role, user_role => $user_role);

EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/02_schemas.sql
  USING (database => $database);

SELECT 'Phase 1 complete' AS status;

-- ============================================================================
-- Phase 2: Core Tables
-- ============================================================================

SELECT '=== Phase 2: Core Tables ===' AS phase;

EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/03_substations.sql
  USING (database => $database, schema => $schema_name);

EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/04_transformers.sql
  USING (database => $database, schema => $schema_name);

EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/05_customers_master.sql
  USING (database => $database, schema => $schema_name);

EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/06_meters.sql
  USING (database => $database, schema => $schema_name);

EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/07_ami_readings.sql
  USING (database => $database, schema => $schema_name);

SELECT 'Phase 2 complete' AS status;

-- ============================================================================
-- Phase 3: Operational Tables
-- ============================================================================

SELECT '=== Phase 3: Operational Tables ===' AS phase;

EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/08_outages.sql
  USING (database => $database, schema => $schema_name);

EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/09_work_orders.sql
  USING (database => $database, schema => $schema_name);

SELECT 'Phase 3 complete' AS status;

-- ============================================================================
-- Phase 4: Analytics Layer
-- ============================================================================

SELECT '=== Phase 4: Analytics Layer ===' AS phase;

EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/10_analytics_views.sql
  USING (database => $database, schema => $schema_name);

EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/11_dynamic_tables.sql
  USING (database => $database, schema => $schema_name, warehouse => $warehouse);

SELECT 'Phase 4 complete' AS status;

-- ============================================================================
-- Phase 5: Cortex AI Setup
-- ============================================================================

SELECT '=== Phase 5: Cortex AI Setup ===' AS phase;

EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/15_cortex_search.sql
  USING (database => $database, schema => $schema_name, warehouse => $warehouse);

EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/16_semantic_view.sql
  USING (database => $database, schema => $schema_name);

EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/17_cortex_agent.sql
  USING (database => $database, schema => $schema_name);

SELECT 'Phase 5 complete' AS status;

-- ============================================================================
-- Phase 6: Application Layer
-- ============================================================================

SELECT '=== Phase 6: Application Layer ===' AS phase;

EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/18_application_views.sql
  USING (database => $database, schema => $schema_name);

SELECT 'Phase 6 complete' AS status;

-- ============================================================================
-- Deployment Complete
-- ============================================================================

SELECT 
  'Flux Utility Solutions deployed successfully!' AS message,
  $database AS database,
  $schema_name AS schema,
  CURRENT_TIMESTAMP() AS deployed_at;
