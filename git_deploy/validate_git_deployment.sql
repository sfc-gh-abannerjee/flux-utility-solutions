-- =============================================================================
-- validate_git_deployment.sql
-- Validates Git Integration deployment path
-- =============================================================================
-- Run after deploying via Git Integration
--
-- Usage:
--   EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/git_deploy/validate_git_deployment.sql
--     USING (database => 'FLUX_PROD');
-- =============================================================================

SET database = COALESCE($database, 'FLUX_PROD');

SELECT '====== GIT INTEGRATION DEPLOYMENT VALIDATION ======' AS validation;
SELECT 'Validating database: ' || $database AS target;

-- =============================================================================
-- SECTION 1: Git Repository Status
-- =============================================================================

SELECT '=== Git Repository Status ===' AS section;

-- Check that the git repository exists
SHOW GIT REPOSITORIES LIKE 'flux%';

-- =============================================================================
-- SECTION 2: Schema Validation
-- =============================================================================

SELECT '=== Schema Validation ===' AS section;

SELECT 
    'Required Schemas' AS check_name,
    COUNT(*) AS schema_count,
    CASE WHEN COUNT(*) >= 5 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.SCHEMATA 
WHERE CATALOG_NAME = $database
AND SCHEMA_NAME IN ('PRODUCTION', 'APPLICATIONS', 'RAW', 'ML', 'ARCHIVE');

-- =============================================================================
-- SECTION 3: Core Tables
-- =============================================================================

SELECT '=== Core Tables ===' AS section;

SELECT 
    TABLE_NAME,
    ROW_COUNT,
    CASE 
        WHEN ROW_COUNT > 0 THEN 'PASS - DATA LOADED'
        ELSE 'WARN - STRUCTURE ONLY'
    END AS status
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = $database
AND TABLE_SCHEMA = 'PRODUCTION'
AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;

-- =============================================================================
-- SECTION 4: View Count
-- =============================================================================

SELECT '=== Views ===' AS section;

SELECT 
    'APPLICATIONS Views' AS check_name,
    COUNT(*) AS view_count,
    CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'WARN' END AS status
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_CATALOG = $database
AND TABLE_SCHEMA = 'APPLICATIONS';

-- =============================================================================
-- SECTION 5: Summary
-- =============================================================================

SELECT '=== DEPLOYMENT SUMMARY ===' AS section;

SELECT 
    $database AS database_name,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE CATALOG_NAME = $database) AS schemas,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_CATALOG = $database AND TABLE_TYPE = 'BASE TABLE') AS tables,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_CATALOG = $database) AS views,
    CURRENT_TIMESTAMP() AS validated_at;

SELECT 'GIT DEPLOYMENT VALIDATION COMPLETE' AS status;
