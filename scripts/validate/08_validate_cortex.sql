-- =============================================================================
-- validate/08_validate_cortex.sql
-- Validates: 08_cortex_search.sql and 09_semantic_model.sql
-- =============================================================================
-- Run after deploying Cortex services
-- Verifies: Cortex Search Services and Semantic Models
-- =============================================================================

USE DATABASE IDENTIFIER('{{ database }}');

SELECT '====== STEP 8 VALIDATION: CORTEX SERVICES ======' AS validation;

-- Check 1: APPLICATIONS schema views
SELECT 
    'APPLICATIONS Views' AS check_name,
    COUNT(*) AS view_count,
    CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'WARN' END AS status
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'APPLICATIONS';

-- Check 2: List all views in APPLICATIONS
SELECT 
    TABLE_NAME AS view_name,
    'VIEW' AS object_type,
    CREATED AS created_at
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'APPLICATIONS'
ORDER BY TABLE_NAME;

-- Check 3: SEMANTIC_MODELS stage exists
SELECT 
    'SEMANTIC_MODELS Stage' AS check_name,
    COUNT(*) AS stage_count,
    CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'WARN' END AS status
FROM INFORMATION_SCHEMA.STAGES
WHERE STAGE_SCHEMA = 'APPLICATIONS' AND STAGE_NAME = 'SEMANTIC_MODELS';

-- Check 4: List stages
SELECT 
    STAGE_NAME,
    STAGE_TYPE,
    CREATED AS created_at
FROM INFORMATION_SCHEMA.STAGES
WHERE STAGE_SCHEMA = 'APPLICATIONS'
ORDER BY STAGE_NAME;

SELECT '====== STEP 8 VALIDATION COMPLETE ======' AS result;

-- =============================================================================
-- MANUAL VALIDATION COMMANDS
-- =============================================================================
-- Run these commands manually to validate Cortex services:
--
-- 1. Check Cortex Search Services:
--    SHOW CORTEX SEARCH SERVICES IN SCHEMA {{ database }}.APPLICATIONS;
--
-- 2. Check Semantic Views:
--    SHOW SEMANTIC VIEWS IN SCHEMA {{ database }}.APPLICATIONS;
--
-- 3. Test Cortex Search (if service exists):
--    SELECT * FROM TABLE(
--      {{ database }}.APPLICATIONS.TRANSFORMER_SEARCH!SEARCH(
--        QUERY => 'overloaded transformer',
--        COLUMNS => ['SEARCH_TEXT'],
--        LIMIT => 5
--      )
--    );
--
-- 4. Test Semantic Model (if exists):
--    SELECT SNOWFLAKE.CORTEX.COMPLETE('claude-3-5-sonnet', 
--      'How many transformers are there?');
-- =============================================================================
