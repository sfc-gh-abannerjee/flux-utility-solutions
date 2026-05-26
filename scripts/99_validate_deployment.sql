-- =============================================================================
-- 99_validate_deployment.sql
-- Flux Utility Solutions - Deployment Validation Script
-- =============================================================================
-- Purpose: Validate that all components were deployed correctly
-- Run after ANY deployment path (SQL, Git, CLI, Terraform)
--
-- Calibrated: 2026-05-26 against se_demo / FLUX_DB (demo scale)
-- Demo scale: 100K meters / 100K customers / ~47K transformers / 288M AMI rows
-- (Full-scale thresholds archived in git history — not valid here)
--
-- Jinja2 Variables:
--   <% database %> - Target database name
--
-- Usage:
--   snow sql -f scripts/99_validate_deployment.sql -D "database='FLUX_DB'" -c se_demo
--
-- Expected Results:
--   - All checks should return 'PASS'
--   - INFO rows are advisory only (expected absent objects in demo)
--   - Object counts calibrated to demo scale (not production full-scale)
-- =============================================================================

-- =============================================================================
-- PRE-FLIGHT: FLUX_WH existence + flow-operator (->>)  probe
-- =============================================================================
-- If this block throws a syntax error, the ->> flow operator is unsupported in
-- this account. In that case, refactor Sections 4 and 9 to the two-statement
-- RESULT_SCAN pattern before re-running.

SHOW WAREHOUSES LIKE 'FLUX_WH'
->>
SELECT
    CASE WHEN COUNT(*) >= 1 THEN 'PASS - FLUX_WH found'
         ELSE 'FAIL - FLUX_WH missing'
    END AS preflight_warehouse_check
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');

-- =============================================================================
-- SECTION 1: SCHEMA VALIDATION
-- =============================================================================
-- Expected: PRODUCTION, APPLICATIONS, RAW, ML_DEMO, CASCADE_ANALYSIS
-- NOTE: Schema was renamed ML -> ML_DEMO. ARCHIVE not deployed in demo (INFO).

SELECT '=== SCHEMA VALIDATION ===' AS section;

WITH expected_schemas AS (
    SELECT 'PRODUCTION'       AS schema_name, TRUE  AS required UNION ALL
    SELECT 'APPLICATIONS',                    TRUE              UNION ALL
    SELECT 'RAW',                             TRUE              UNION ALL
    SELECT 'ML_DEMO',                         TRUE              UNION ALL
    SELECT 'CASCADE_ANALYSIS',                TRUE              UNION ALL
    SELECT 'ARCHIVE',                         FALSE             -- INFO: not deployed in demo
),
actual_schemas AS (
    SELECT SCHEMA_NAME
    FROM INFORMATION_SCHEMA.SCHEMATA
    WHERE CATALOG_NAME = '<% database %>'
    AND SCHEMA_NAME NOT IN ('INFORMATION_SCHEMA', 'PUBLIC')
)
SELECT
    e.schema_name,
    CASE
        WHEN a.schema_name IS NOT NULL THEN 'PASS'
        WHEN NOT e.required            THEN 'INFO - not deployed in demo'
        ELSE                                'FAIL'
    END AS status
FROM expected_schemas e
LEFT JOIN actual_schemas a ON e.schema_name = a.schema_name
ORDER BY e.required DESC, e.schema_name;

-- =============================================================================
-- SECTION 2: PRODUCTION TABLE VALIDATION
-- =============================================================================
-- Thresholds calibrated 2026-05-26 to demo scale:
--   SUBSTATIONS 25 | TRANSFORMER_METADATA ~47K | CIRCUIT_METADATA 50
--   METER_INFRASTRUCTURE 100K | CUSTOMERS_MASTER_DATA 100K
--   AMI_INTERVAL_READINGS 288M | TRANSFORMER_HOURLY_LOAD 33.87M
--   HOUSTON_WEATHER_HOURLY 720
-- Tables absent in demo (AMI_MONTHLY_USAGE, OUTAGE_EVENTS, VOLTAGE_SAG_EVENTS)
-- are INFO-only — will not produce FAIL.

SELECT '=== PRODUCTION TABLES ===' AS section;

WITH expected_tables AS (
    SELECT 'SUBSTATIONS'           AS table_name, 1         AS min_expected_rows, TRUE  AS required UNION ALL
    SELECT 'TRANSFORMER_METADATA',                40000,                           TRUE              UNION ALL
    SELECT 'CIRCUIT_METADATA',                    1,                               TRUE              UNION ALL
    SELECT 'METER_INFRASTRUCTURE',                99000,                           TRUE              UNION ALL
    SELECT 'CUSTOMERS_MASTER_DATA',               99000,                           TRUE              UNION ALL
    SELECT 'AMI_INTERVAL_READINGS',               100000000,                       TRUE              UNION ALL
    SELECT 'TRANSFORMER_HOURLY_LOAD',             30000000,                        TRUE              UNION ALL
    SELECT 'HOUSTON_WEATHER_HOURLY',              700,                             TRUE              UNION ALL
    SELECT 'AMI_MONTHLY_USAGE',                   0,                               FALSE             UNION ALL  -- INFO: not deployed in demo
    SELECT 'OUTAGE_EVENTS',                       0,                               FALSE             UNION ALL  -- INFO: not deployed in demo
    SELECT 'VOLTAGE_SAG_EVENTS',                  0,                               FALSE                        -- INFO: not deployed in demo
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
        WHEN NOT e.required                     THEN 'INFO - not deployed in demo'
        WHEN a.table_name IS NULL               THEN 'FAIL - TABLE MISSING'
        WHEN a.row_count >= e.min_expected_rows THEN 'PASS'
        WHEN a.row_count > 0                    THEN 'WARN - LOW ROW COUNT'
        ELSE                                         'WARN - EMPTY TABLE'
    END AS status
FROM expected_tables e
LEFT JOIN actual_tables a ON e.table_name = a.table_name
ORDER BY e.required DESC, e.table_name;

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
-- CRITICAL: SHOW must use IN DATABASE scope (not IN SCHEMA).
-- Search services span 3 schemas: APPLICATIONS (2), ML_DEMO (1), PRODUCTION (1).
-- A SCHEMA-scoped SHOW returns only 2 of 4 → guaranteed FAIL.

SELECT '=== CORTEX SERVICES ===' AS section;

-- Cortex Search Services — DATABASE scope
SHOW CORTEX SEARCH SERVICES IN DATABASE <% database %>
->>
SELECT
    'Cortex Search Services' AS service_type,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) >= 4 THEN 'PASS'
         ELSE 'FAIL - expected >= 4, found: ' || COUNT(*)::STRING
    END AS status,
    LISTAGG("name", ', ') AS services
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Semantic Views — DATABASE scope
SHOW SEMANTIC VIEWS IN DATABASE <% database %>
->>
SELECT
    'Semantic Views' AS service_type,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) >= 1 THEN 'PASS'
         ELSE 'FAIL - expected >= 1'
    END AS status,
    LISTAGG("name", ', ') AS views
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- =============================================================================
-- SECTION 5: WAREHOUSE VALIDATION
-- =============================================================================

SELECT '=== WAREHOUSE CHECK ===' AS section;

SELECT
    'Warehouse Access' AS check_type,
    CURRENT_WAREHOUSE() AS current_warehouse,
    CASE
      WHEN CURRENT_WAREHOUSE() IS NULL THEN 'FAIL - no warehouse'
      WHEN CURRENT_WAREHOUSE() != 'FLUX_WH' THEN 'WARN - running on ' || CURRENT_WAREHOUSE() || ', expected FLUX_WH'
      ELSE 'PASS'
    END AS status;

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
-- NOTE: AMI column is READING_TIMESTAMP (TIMESTAMP_NTZ), NOT bare TIMESTAMP.
-- TIMESTAMP is a Snowflake reserved keyword — never use as a column reference.
-- Actual data range: 2024-07-01 00:00 .. 2024-07-30 23:45 (BACKFILL30 window).

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

-- Check AMI timestamp range using READING_TIMESTAMP (actual MAX: 2024-07-30 23:45)
SELECT
    'AMI Data Range' AS check_type,
    MIN(READING_TIMESTAMP)::DATE AS earliest_date,
    MAX(READING_TIMESTAMP)::DATE AS latest_date,
    DATEDIFF('day', MIN(READING_TIMESTAMP), MAX(READING_TIMESTAMP)) AS date_range_days,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'WARN - NO DATA' END AS status
FROM PRODUCTION.AMI_INTERVAL_READINGS
WHERE READING_TIMESTAMP IS NOT NULL;

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
-- SECTION 9: AGENT VALIDATION
-- =============================================================================
-- Verifies GRID_INTELLIGENCE_AGENT exists and has >= 5 tools.
-- DESCRIBE AGENT (not SHOW AGENTS) is required — only DESCRIBE exposes the full
-- tool spec. Result column is agent_spec (quoted lowercase in RESULT_SCAN).

SELECT '=== AGENT VALIDATION ===' AS section;

DESCRIBE AGENT <% database %>.APPLICATIONS.GRID_INTELLIGENCE_AGENT;

SELECT
    CASE WHEN ARRAY_SIZE(PARSE_JSON("agent_spec"):tools) >= 5
         THEN 'PASS'
         ELSE 'FAIL - expected >= 5 tools, got: ' || ARRAY_SIZE(PARSE_JSON("agent_spec"):tools)::STRING
    END AS agent_check,
    ARRAY_SIZE(PARSE_JSON("agent_spec"):tools) AS tool_count
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- =============================================================================
-- SECTION 10: SEMANTIC VIEW ROUNDTRIP
-- =============================================================================
-- Confirms UTILITY_SEMANTIC_VIEW is functional (not just registered).
-- NOTE: Semantic views are not queryable via plain SELECT COUNT(*) — they require
-- dimension/metric/fact query syntax. DESCRIBE is the correct functional probe:
-- it resolves the view's full schema and errors if the object is corrupt or missing.
-- Pass if DESCRIBE returns without error.

SELECT '=== SEMANTIC VIEW ROUNDTRIP ===' AS section;

DESCRIBE SEMANTIC VIEW <% database %>.APPLICATIONS.UTILITY_SEMANTIC_VIEW;

-- =============================================================================
-- MANUAL CHECKS (Run separately)
-- =============================================================================
/*
-- Check Cortex Search Services (DATABASE scope to see all 4):
SHOW CORTEX SEARCH SERVICES IN DATABASE <% database %>;

-- Check Semantic Views:
SHOW SEMANTIC VIEWS IN DATABASE <% database %>;

-- Check Cortex Agents:
SHOW AGENTS IN SCHEMA <% database %>.APPLICATIONS;

-- Check SPCS Services (if deployed):
SHOW SERVICES IN SCHEMA <% database %>.APPLICATIONS;

-- Check Compute Pools:
SHOW COMPUTE POOLS;

-- Test Semantic View (if exists):
SELECT SNOWFLAKE.CORTEX.COMPLETE('claude-3-5-sonnet',
    'Based on the semantic view, how many transformers are there?');
*/

SELECT 'VALIDATION COMPLETE' AS status,
       'Review results above for any FAIL statuses. WARN = advisory. INFO = expected absent in demo.' AS message;
