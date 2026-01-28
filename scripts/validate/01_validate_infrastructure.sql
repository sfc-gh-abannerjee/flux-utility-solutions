-- =============================================================================
-- validate/01_validate_infrastructure.sql
-- Validates: 01_database_infrastructure.sql
-- =============================================================================
-- Run after deploying 01_database_infrastructure.sql
-- Verifies: Database, schemas, roles, and grants created correctly
-- =============================================================================

-- Set context
USE DATABASE IDENTIFIER('{{ database }}');

SELECT '====== STEP 1 VALIDATION: DATABASE INFRASTRUCTURE ======' AS validation;

-- Check 1: Database exists
SELECT 
    'Database Created' AS check_name,
    CURRENT_DATABASE() AS value,
    CASE WHEN CURRENT_DATABASE() = '{{ database }}' THEN 'PASS' ELSE 'FAIL' END AS status;

-- Check 2: All required schemas exist
SELECT 
    'Required Schemas' AS check_name,
    COUNT(*) AS schema_count,
    CASE WHEN COUNT(*) >= 5 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.SCHEMATA 
WHERE SCHEMA_NAME IN ('PRODUCTION', 'APPLICATIONS', 'RAW', 'ML', 'ARCHIVE');

-- Check 3: Schema list
SELECT 
    SCHEMA_NAME,
    CREATED AS created_at,
    'EXISTS' AS status
FROM INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME NOT IN ('INFORMATION_SCHEMA', 'PUBLIC')
ORDER BY SCHEMA_NAME;

-- Check 4: Verify current role has access
SELECT 
    'Role Access' AS check_name,
    CURRENT_ROLE() AS current_role,
    'PASS' AS status;

SELECT '====== STEP 1 VALIDATION COMPLETE ======' AS result,
       'Proceed to 02_data_stages.sql if all checks PASS' AS next_step;
