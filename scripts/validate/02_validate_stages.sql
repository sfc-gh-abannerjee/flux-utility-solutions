-- =============================================================================
-- validate/02_validate_stages.sql
-- Validates: 02_data_stages.sql
-- =============================================================================
-- Run after deploying 02_data_stages.sql
-- Verifies: External stages and seed data stages created
-- =============================================================================

USE DATABASE IDENTIFIER('{{ database }}');

SELECT '====== STEP 2 VALIDATION: DATA STAGES ======' AS validation;

-- Check 1: Stages in PRODUCTION schema
SELECT 
    'PRODUCTION Stages' AS check_name,
    COUNT(*) AS stage_count,
    CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'WARN - No stages found' END AS status
FROM INFORMATION_SCHEMA.STAGES
WHERE STAGE_SCHEMA = 'PRODUCTION';

-- Check 2: Stages in APPLICATIONS schema
SELECT 
    'APPLICATIONS Stages' AS check_name,
    COUNT(*) AS stage_count,
    CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'WARN - No stages found' END AS status
FROM INFORMATION_SCHEMA.STAGES
WHERE STAGE_SCHEMA = 'APPLICATIONS';

-- Check 3: List all stages
SELECT 
    STAGE_SCHEMA,
    STAGE_NAME,
    STAGE_TYPE,
    CREATED AS created_at
FROM INFORMATION_SCHEMA.STAGES
WHERE STAGE_SCHEMA NOT IN ('INFORMATION_SCHEMA', 'PUBLIC')
ORDER BY STAGE_SCHEMA, STAGE_NAME;

SELECT '====== STEP 2 VALIDATION COMPLETE ======' AS result,
       'Proceed to 03_substations_transformers.sql if all checks PASS' AS next_step;
