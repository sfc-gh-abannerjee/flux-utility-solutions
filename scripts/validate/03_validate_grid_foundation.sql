-- =============================================================================
-- validate/03_validate_grid_foundation.sql
-- Validates: 03_substations_transformers.sql
-- =============================================================================
-- Run after deploying 03_substations_transformers.sql
-- Verifies: Grid foundation tables (substations, transformers, circuits)
-- =============================================================================

USE DATABASE IDENTIFIER('{{ database }}');

SELECT '====== STEP 3 VALIDATION: GRID FOUNDATION ======' AS validation;

-- Check 1: SUBSTATIONS table
SELECT 
    'SUBSTATIONS Table' AS check_name,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
     WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'SUBSTATIONS') AS table_exists,
    CASE 
        WHEN (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
              WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'SUBSTATIONS') = 1 
        THEN 'PASS' 
        ELSE 'FAIL' 
    END AS status;

-- Check 2: TRANSFORMER_METADATA table
SELECT 
    'TRANSFORMER_METADATA Table' AS check_name,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
     WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'TRANSFORMER_METADATA') AS table_exists,
    CASE 
        WHEN (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
              WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'TRANSFORMER_METADATA') = 1 
        THEN 'PASS' 
        ELSE 'FAIL' 
    END AS status;

-- Check 3: CIRCUIT_METADATA table
SELECT 
    'CIRCUIT_METADATA Table' AS check_name,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
     WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'CIRCUIT_METADATA') AS table_exists,
    CASE 
        WHEN (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
              WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'CIRCUIT_METADATA') = 1 
        THEN 'PASS' 
        ELSE 'FAIL' 
    END AS status;

-- Check 4: Table row counts (structure only - data loaded separately)
SELECT 
    TABLE_NAME,
    ROW_COUNT,
    CASE 
        WHEN ROW_COUNT > 0 THEN 'DATA LOADED'
        ELSE 'STRUCTURE ONLY'
    END AS data_status
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'PRODUCTION'
AND TABLE_NAME IN ('SUBSTATIONS', 'TRANSFORMER_METADATA', 'CIRCUIT_METADATA')
ORDER BY TABLE_NAME;

-- Check 5: Column validation for SUBSTATIONS
SELECT 
    'SUBSTATIONS Columns' AS check_name,
    COUNT(*) AS column_count,
    CASE WHEN COUNT(*) >= 5 THEN 'PASS' ELSE 'WARN' END AS status
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'SUBSTATIONS';

-- Check 6: Column validation for TRANSFORMER_METADATA
SELECT 
    'TRANSFORMER_METADATA Columns' AS check_name,
    COUNT(*) AS column_count,
    CASE WHEN COUNT(*) >= 8 THEN 'PASS' ELSE 'WARN' END AS status
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'TRANSFORMER_METADATA';

SELECT '====== STEP 3 VALIDATION COMPLETE ======' AS result,
       'Proceed to 04_meters_infrastructure.sql if all checks PASS' AS next_step;
