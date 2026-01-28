-- =============================================================================
-- 99_validate_deployment.sql
-- Flux Utility Solutions - Deployment Validation Script
-- =============================================================================
-- Purpose: Validate that all components were deployed correctly
-- Run after ANY deployment path (SQL, Git, CLI, Terraform)
--
-- Jinja2 Variables:
--   <% database %> - Target database name
--
-- Usage:
--   snow sql -f scripts/99_validate_deployment.sql -D "database='FLUX_PROD'"
--
-- Expected Results:
--   - All checks should return 'PASS'
--   - Object counts should match expected minimums
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');

-- =============================================================================
-- SECTION 1: SCHEMA VALIDATION
-- =============================================================================
-- Expected: 5 user schemas (PRODUCTION, APPLICATIONS, RAW, ML, ARCHIVE)

SELECT '=== SCHEMA VALIDATION ===' AS section;

WITH expected_schemas AS (
    SELECT 'PRODUCTION' AS schema_name UNION ALL
    SELECT 'APPLICATIONS' UNION ALL
    SELECT 'RAW' UNION ALL
    SELECT 'ML' UNION ALL
    SELECT 'ARCHIVE'
),
actual_schemas AS (
    SELECT SCHEMA_NAME 
    FROM INFORMATION_SCHEMA.SCHEMATA 
    WHERE CATALOG_NAME = '<% database %>'
    AND SCHEMA_NAME NOT IN ('INFORMATION_SCHEMA', 'PUBLIC')
)
SELECT 
    e.schema_name,
    CASE WHEN a.schema_name IS NOT NULL THEN 'PASS' ELSE 'FAIL' END AS status
FROM expected_schemas e
LEFT JOIN actual_schemas a ON e.schema_name = a.schema_name
ORDER BY e.schema_name;

-- =============================================================================
-- SECTION 2: PRODUCTION TABLE VALIDATION
-- =============================================================================
-- Expected: Core dimension and fact tables

SELECT '=== PRODUCTION TABLES ===' AS section;

WITH expected_tables AS (
    SELECT 'SUBSTATIONS' AS table_name, 275 AS min_expected_rows UNION ALL
    SELECT 'TRANSFORMER_METADATA', 90000 UNION ALL
    SELECT 'CIRCUIT_METADATA', 70 UNION ALL
    SELECT 'METER_INFRASTRUCTURE', 590000 UNION ALL
    SELECT 'CUSTOMERS_MASTER_DATA', 680000 UNION ALL
    SELECT 'AMI_INTERVAL_READINGS', 1000000 UNION ALL
    SELECT 'AMI_MONTHLY_USAGE', 100000 UNION ALL
    SELECT 'TRANSFORMER_HOURLY_LOAD', 1000000 UNION ALL
    SELECT 'OUTAGE_EVENTS', 1000 UNION ALL
    SELECT 'VOLTAGE_SAG_EVENTS', 1000
),
actual_tables AS (
    SELECT TABLE_NAME, ROW_COUNT
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'PRODUCTION'
    AND TABLE_TYPE = 'BASE TABLE'
)
SELECT 
    e.table_name,
    COALESCE(a.row_count, 0) AS actual_rows,
    e.min_expected_rows,
    CASE 
        WHEN a.table_name IS NULL THEN 'FAIL - TABLE MISSING'
        WHEN a.row_count >= e.min_expected_rows THEN 'PASS'
        WHEN a.row_count > 0 THEN 'WARN - LOW ROW COUNT'
        ELSE 'WARN - EMPTY TABLE'
    END AS status
FROM expected_tables e
LEFT JOIN actual_tables a ON e.table_name = a.table_name
ORDER BY e.table_name;

-- =============================================================================
-- SECTION 3: APPLICATIONS OBJECTS VALIDATION  
-- =============================================================================

SELECT '=== APPLICATIONS OBJECTS ===' AS section;

-- Check for views
SELECT 
    'Views in APPLICATIONS' AS check_type,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'WARN' END AS status
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'APPLICATIONS';

-- Check for stages
SELECT 
    'Stages in APPLICATIONS' AS check_type,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'WARN' END AS status
FROM INFORMATION_SCHEMA.STAGES
WHERE STAGE_SCHEMA = 'APPLICATIONS';

-- =============================================================================
-- SECTION 4: CORTEX SERVICES VALIDATION
-- =============================================================================

SELECT '=== CORTEX SERVICES ===' AS section;

-- Check Cortex Search Services
SELECT 
    'Cortex Search Services' AS service_type,
    COUNT(*) AS count,
    LISTAGG(DATABASE_NAME || '.' || SCHEMA_NAME || '.' || NAME, ', ') AS services
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID(-1)))
WHERE 1=0;  -- Placeholder - actual check requires SHOW command

-- Note: Run these manually to check Cortex services:
-- SHOW CORTEX SEARCH SERVICES IN SCHEMA <% database %>.APPLICATIONS;
-- SHOW SEMANTIC VIEWS IN SCHEMA <% database %>.APPLICATIONS;

-- =============================================================================
-- SECTION 5: WAREHOUSE VALIDATION
-- =============================================================================

SELECT '=== WAREHOUSE CHECK ===' AS section;

-- Warehouses should be accessible
SELECT 
    'Warehouse Access' AS check_type,
    CURRENT_WAREHOUSE() AS current_warehouse,
    CASE WHEN CURRENT_WAREHOUSE() IS NOT NULL THEN 'PASS' ELSE 'FAIL' END AS status;

-- =============================================================================
-- SECTION 6: ROLE VALIDATION
-- =============================================================================

SELECT '=== ROLE CHECK ===' AS section;

SELECT 
    'Current Role' AS check_type,
    CURRENT_ROLE() AS current_role,
    'INFO' AS status;

-- =============================================================================
-- SECTION 7: DATA QUALITY CHECKS
-- =============================================================================

SELECT '=== DATA QUALITY ===' AS section;

-- Check for orphaned records (meters without transformers)
SELECT 
    'Meters with valid transformer' AS check_type,
    COUNT(*) AS meters_with_transformer,
    (SELECT COUNT(*) FROM PRODUCTION.METER_INFRASTRUCTURE) AS total_meters,
    CASE 
        WHEN COUNT(*) = (SELECT COUNT(*) FROM PRODUCTION.METER_INFRASTRUCTURE) THEN 'PASS'
        ELSE 'WARN - ORPHANED METERS'
    END AS status
FROM PRODUCTION.METER_INFRASTRUCTURE mi
WHERE EXISTS (
    SELECT 1 FROM PRODUCTION.TRANSFORMER_METADATA tm 
    WHERE tm.TRANSFORMER_ID = mi.TRANSFORMER_ID
);

-- Check AMI timestamp range
SELECT 
    'AMI Data Range' AS check_type,
    MIN(TIMESTAMP)::DATE AS earliest_date,
    MAX(TIMESTAMP)::DATE AS latest_date,
    DATEDIFF('day', MIN(TIMESTAMP), MAX(TIMESTAMP)) AS date_range_days,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'WARN - NO DATA' END AS status
FROM PRODUCTION.AMI_INTERVAL_READINGS
WHERE TIMESTAMP IS NOT NULL;

-- =============================================================================
-- SECTION 8: SUMMARY
-- =============================================================================

SELECT '=== DEPLOYMENT SUMMARY ===' AS section;

SELECT 
    '<% database %>' AS database_name,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE CATALOG_NAME = '<% database %>') AS schema_count,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_CATALOG = '<% database %>' AND TABLE_TYPE = 'BASE TABLE') AS table_count,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_CATALOG = '<% database %>') AS view_count,
    (SELECT SUM(ROW_COUNT) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_CATALOG = '<% database %>' AND TABLE_TYPE = 'BASE TABLE') AS total_rows,
    CURRENT_TIMESTAMP() AS validated_at;

-- =============================================================================
-- MANUAL CHECKS (Run separately)
-- =============================================================================
/*
-- Check Cortex Search Services:
SHOW CORTEX SEARCH SERVICES IN SCHEMA <% database %>.APPLICATIONS;

-- Check Semantic Views:
SHOW SEMANTIC VIEWS IN SCHEMA <% database %>.APPLICATIONS;

-- Check Cortex Agents:
SHOW CORTEX AGENTS IN SCHEMA <% database %>.APPLICATIONS;

-- Check SPCS Services (if deployed):
SHOW SERVICES IN SCHEMA <% database %>.APPLICATIONS;

-- Check Compute Pools:
SHOW COMPUTE POOLS;

-- Test Semantic View (if exists):
SELECT SNOWFLAKE.CORTEX.COMPLETE('claude-3-5-sonnet', 
    'Based on the semantic view, how many transformers are there?');
*/

SELECT 'VALIDATION COMPLETE' AS status, 
       'Review results above for any FAIL or WARN statuses' AS message;
