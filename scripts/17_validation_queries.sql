-- =============================================================================
-- 17_validation_queries.sql
-- Flux Utility Solutions - Deployment Validation Suite
-- =============================================================================
-- Purpose: Validate deployment matches production and all components work
-- Dependencies: All previous scripts (01-16)
-- Jinja2 Variables:
--   <% database %>    - Target database name
--   <% source_db %>   - Source database to compare against (e.g., SI_DEMOS)
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');

-- -----------------------------------------------------------------------------
-- 1. SCHEMA VALIDATION
-- -----------------------------------------------------------------------------

-- Verify all required schemas exist
SELECT 'SCHEMA_CHECK' AS CHECK_TYPE,
       SCHEMA_NAME,
       CASE WHEN SCHEMA_NAME IN ('PRODUCTION', 'APPLICATIONS', 'SECRETS') 
            THEN 'PASS' ELSE 'UNEXPECTED' END AS STATUS
FROM INFORMATION_SCHEMA.SCHEMATA
WHERE CATALOG_NAME = '<% database %>';

-- -----------------------------------------------------------------------------
-- 2. TABLE COUNT VALIDATION
-- -----------------------------------------------------------------------------

-- Compare table counts between environments
WITH source_tables AS (
    SELECT TABLE_NAME, ROW_COUNT 
    FROM <% source_db %>.INFORMATION_SCHEMA.TABLES 
    WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_TYPE = 'BASE TABLE'
),
target_tables AS (
    SELECT TABLE_NAME, ROW_COUNT 
    FROM <% database %>.INFORMATION_SCHEMA.TABLES 
    WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_TYPE = 'BASE TABLE'
)
SELECT 
    'TABLE_COUNT' AS CHECK_TYPE,
    COALESCE(s.TABLE_NAME, t.TABLE_NAME) AS TABLE_NAME,
    s.ROW_COUNT AS SOURCE_ROWS,
    t.ROW_COUNT AS TARGET_ROWS,
    CASE 
        WHEN t.TABLE_NAME IS NULL THEN 'MISSING'
        WHEN s.TABLE_NAME IS NULL THEN 'NEW_TABLE'
        WHEN s.ROW_COUNT = t.ROW_COUNT THEN 'PASS'
        ELSE 'ROW_COUNT_DIFF'
    END AS STATUS
FROM source_tables s
FULL OUTER JOIN target_tables t ON s.TABLE_NAME = t.TABLE_NAME
ORDER BY STATUS DESC, TABLE_NAME;

-- -----------------------------------------------------------------------------
-- 3. KEY TABLE ROW COUNTS
-- -----------------------------------------------------------------------------

SELECT 'KEY_TABLES' AS CHECK_TYPE, * FROM (
    SELECT 'AMI_INTERVAL_READINGS' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM PRODUCTION.AMI_INTERVAL_READINGS
    UNION ALL
    SELECT 'TRANSFORMER_METADATA', COUNT(*) FROM PRODUCTION.TRANSFORMER_METADATA
    UNION ALL
    SELECT 'TRANSFORMER_HOURLY_LOAD', COUNT(*) FROM PRODUCTION.TRANSFORMER_HOURLY_LOAD
    UNION ALL
    SELECT 'CUSTOMERS_MASTER_DATA', COUNT(*) FROM PRODUCTION.CUSTOMERS_MASTER_DATA
    UNION ALL
    SELECT 'METER_INFRASTRUCTURE', COUNT(*) FROM PRODUCTION.METER_INFRASTRUCTURE
    UNION ALL
    SELECT 'SUBSTATIONS', COUNT(*) FROM PRODUCTION.SUBSTATIONS
);

-- -----------------------------------------------------------------------------
-- 4. SEMANTIC VIEW VALIDATION
-- -----------------------------------------------------------------------------

-- Check semantic view exists and is queryable
SELECT 'SEMANTIC_VIEW' AS CHECK_TYPE,
       SEMANTIC_VIEW_NAME,
       COMMENT,
       CREATED AS CREATED_AT,
       'PASS' AS STATUS
FROM INFORMATION_SCHEMA.SEMANTIC_VIEWS
WHERE SEMANTIC_VIEW_SCHEMA = 'APPLICATIONS';

-- Test semantic view column extraction
SELECT 'SEMANTIC_COLUMNS' AS CHECK_TYPE,
       COUNT(*) AS COLUMN_COUNT,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM TABLE(
    SNOWFLAKE.CORTEX.SEMANTIC_VIEW_COLUMNS('<% database %>.APPLICATIONS.UTILITY_SEMANTIC_VIEW')
);

-- -----------------------------------------------------------------------------
-- 5. CORTEX SEARCH SERVICE VALIDATION
-- -----------------------------------------------------------------------------

SELECT 'SEARCH_SERVICES' AS CHECK_TYPE,
       NAME AS SERVICE_NAME,
       TARGET_LAG,
       COMMENT,
       'PASS' AS STATUS
FROM INFORMATION_SCHEMA.CORTEX_SEARCH_SERVICES
WHERE SCHEMA_NAME = 'APPLICATIONS';

-- Test search service (basic query)
SELECT 'SEARCH_TEST' AS CHECK_TYPE,
       'CUSTOMER_SEARCH_SERVICE' AS SERVICE_NAME,
       CASE 
           WHEN RESULT IS NOT NULL THEN 'PASS' 
           ELSE 'FAIL' 
       END AS STATUS
FROM (
    SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        '<% database %>.APPLICATIONS.CUSTOMER_SEARCH_SERVICE',
        '{"query": "residential Houston", "columns": ["CUSTOMER_ID"], "limit": 1}'
    ) AS RESULT
);

-- -----------------------------------------------------------------------------
-- 6. CORTEX AGENT VALIDATION
-- -----------------------------------------------------------------------------

SELECT 'AGENTS' AS CHECK_TYPE,
       NAME AS AGENT_NAME,
       COMMENT,
       CREATED AS CREATED_AT,
       'PASS' AS STATUS
FROM INFORMATION_SCHEMA.AGENTS
WHERE SCHEMA_NAME = 'APPLICATIONS';

-- -----------------------------------------------------------------------------
-- 7. WAREHOUSE VALIDATION
-- -----------------------------------------------------------------------------

SELECT 'WAREHOUSES' AS CHECK_TYPE,
       NAME AS WAREHOUSE_NAME,
       SIZE,
       STATE,
       CASE WHEN STATE IN ('STARTED', 'SUSPENDED') THEN 'PASS' ELSE 'CHECK' END AS STATUS
FROM INFORMATION_SCHEMA.WAREHOUSES
WHERE NAME LIKE '<% warehouse %>%' OR NAME LIKE 'FLUX%';

-- -----------------------------------------------------------------------------
-- 8. SPCS SERVICE VALIDATION
-- -----------------------------------------------------------------------------

SHOW SERVICES IN SCHEMA APPLICATIONS;

-- Check service status
SELECT 'SPCS_SERVICES' AS CHECK_TYPE,
       "name" AS SERVICE_NAME,
       "status" AS STATUS,
       "min_instances" AS MIN_INSTANCES,
       "max_instances" AS MAX_INSTANCES,
       CASE WHEN "status" IN ('READY', 'PENDING') THEN 'PASS' ELSE 'CHECK' END AS VALIDATION
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- -----------------------------------------------------------------------------
-- 9. ROLE AND GRANTS VALIDATION
-- -----------------------------------------------------------------------------

-- Check roles exist
SELECT 'ROLES' AS CHECK_TYPE,
       NAME AS ROLE_NAME,
       CREATED_ON,
       'PASS' AS STATUS
FROM SNOWFLAKE.ACCOUNT_USAGE.ROLES
WHERE NAME IN ('<% admin_role %>', '<% user_role %>', 'FLUX_ANALYST_ROLE', 'FLUX_ETL_ROLE')
  AND DELETED_ON IS NULL;

-- Check key grants
SELECT 'GRANTS' AS CHECK_TYPE,
       GRANTEE_NAME,
       PRIVILEGE,
       GRANTED_ON,
       NAME AS OBJECT_NAME,
       'PASS' AS STATUS
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE GRANTEE_NAME IN ('<% admin_role %>', '<% user_role %>')
  AND DELETED_ON IS NULL
  AND GRANTED_ON IN ('DATABASE', 'SCHEMA', 'SEMANTIC_VIEW')
LIMIT 20;

-- -----------------------------------------------------------------------------
-- 10. DATA QUALITY CHECKS
-- -----------------------------------------------------------------------------

-- Check for null primary keys
SELECT 'DATA_QUALITY' AS CHECK_TYPE,
       'NULL_KEYS_AMI' AS CHECK_NAME,
       COUNT(*) AS ISSUE_COUNT,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM PRODUCTION.AMI_INTERVAL_READINGS
WHERE METER_ID IS NULL OR TIMESTAMP IS NULL;

SELECT 'DATA_QUALITY' AS CHECK_TYPE,
       'NULL_KEYS_XFMR' AS CHECK_NAME,
       COUNT(*) AS ISSUE_COUNT,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM PRODUCTION.TRANSFORMER_METADATA
WHERE TRANSFORMER_ID IS NULL;

-- Check date ranges
SELECT 'DATA_QUALITY' AS CHECK_TYPE,
       'AMI_DATE_RANGE' AS CHECK_NAME,
       MIN(TIMESTAMP) AS MIN_DATE,
       MAX(TIMESTAMP) AS MAX_DATE,
       DATEDIFF('day', MIN(TIMESTAMP), MAX(TIMESTAMP)) AS DAYS_SPAN,
       'INFO' AS STATUS
FROM PRODUCTION.AMI_INTERVAL_READINGS;

-- -----------------------------------------------------------------------------
-- 11. DEPLOYMENT SUMMARY
-- -----------------------------------------------------------------------------

SELECT 
    '=== FLUX DEPLOYMENT VALIDATION SUMMARY ===' AS REPORT,
    CURRENT_DATABASE() AS DATABASE,
    CURRENT_TIMESTAMP() AS VALIDATED_AT;

SELECT 
    COUNT(DISTINCT TABLE_NAME) AS TABLES,
    COUNT(DISTINCT CASE WHEN TABLE_TYPE = 'VIEW' THEN TABLE_NAME END) AS VIEWS,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.SEMANTIC_VIEWS WHERE SEMANTIC_VIEW_SCHEMA = 'APPLICATIONS') AS SEMANTIC_VIEWS,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.CORTEX_SEARCH_SERVICES WHERE SCHEMA_NAME = 'APPLICATIONS') AS SEARCH_SERVICES
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN ('PRODUCTION', 'APPLICATIONS');

-- =============================================================================
-- VALIDATION COMPLETE
-- Review results above. All checks should show 'PASS' status.
-- If any show 'FAIL' or 'MISSING', investigate and fix before proceeding.
-- Next: Run 18_deploy_orchestrator.sql for automated deployment
-- =============================================================================
