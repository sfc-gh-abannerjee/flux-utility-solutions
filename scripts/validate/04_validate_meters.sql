-- =============================================================================
-- validate/04_validate_meters.sql
-- Validates: 04_meters_infrastructure.sql
-- =============================================================================
-- Run after deploying 04_meters_infrastructure.sql
-- Verifies: Meter infrastructure tables
-- =============================================================================

USE DATABASE IDENTIFIER('{{ database }}');

SELECT '====== STEP 4 VALIDATION: METER INFRASTRUCTURE ======' AS validation;

-- Check 1: METER_INFRASTRUCTURE table exists
SELECT 
    'METER_INFRASTRUCTURE Table' AS check_name,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
     WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'METER_INFRASTRUCTURE') AS table_exists,
    CASE 
        WHEN (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
              WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'METER_INFRASTRUCTURE') = 1 
        THEN 'PASS' 
        ELSE 'FAIL' 
    END AS status;

-- Check 2: Column count
SELECT 
    'METER_INFRASTRUCTURE Columns' AS check_name,
    COUNT(*) AS column_count,
    CASE WHEN COUNT(*) >= 6 THEN 'PASS' ELSE 'WARN' END AS status
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'METER_INFRASTRUCTURE';

-- Check 3: Key columns exist
SELECT 
    COLUMN_NAME,
    DATA_TYPE,
    'EXISTS' AS status
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'PRODUCTION' 
AND TABLE_NAME = 'METER_INFRASTRUCTURE'
AND COLUMN_NAME IN ('METER_ID', 'TRANSFORMER_ID', 'CUSTOMER_ID', 'METER_TYPE', 'INSTALL_DATE')
ORDER BY ORDINAL_POSITION;

-- Check 4: Row count
SELECT 
    'METER_INFRASTRUCTURE Data' AS check_name,
    (SELECT ROW_COUNT FROM INFORMATION_SCHEMA.TABLES 
     WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'METER_INFRASTRUCTURE') AS row_count,
    CASE 
        WHEN (SELECT ROW_COUNT FROM INFORMATION_SCHEMA.TABLES 
              WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'METER_INFRASTRUCTURE') > 0 
        THEN 'DATA LOADED'
        ELSE 'STRUCTURE ONLY'
    END AS data_status;

SELECT '====== STEP 4 VALIDATION COMPLETE ======' AS result,
       'Proceed to 05_customers_master.sql if all checks PASS' AS next_step;
