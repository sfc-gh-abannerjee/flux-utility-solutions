-- =============================================================================
-- validate/05_validate_customers.sql
-- Validates: 05_customers_master.sql
-- =============================================================================
-- Run after deploying 05_customers_master.sql
-- Verifies: Customer master data table
-- =============================================================================

USE DATABASE IDENTIFIER('{{ database }}');

SELECT '====== STEP 5 VALIDATION: CUSTOMER MASTER DATA ======' AS validation;

-- Check 1: CUSTOMERS_MASTER_DATA table exists
SELECT 
    'CUSTOMERS_MASTER_DATA Table' AS check_name,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
     WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'CUSTOMERS_MASTER_DATA') AS table_exists,
    CASE 
        WHEN (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
              WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'CUSTOMERS_MASTER_DATA') = 1 
        THEN 'PASS' 
        ELSE 'FAIL' 
    END AS status;

-- Check 2: Column count
SELECT 
    'CUSTOMERS_MASTER_DATA Columns' AS check_name,
    COUNT(*) AS column_count,
    CASE WHEN COUNT(*) >= 8 THEN 'PASS' ELSE 'WARN' END AS status
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'CUSTOMERS_MASTER_DATA';

-- Check 3: Key columns exist
SELECT 
    COLUMN_NAME,
    DATA_TYPE,
    'EXISTS' AS status
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'PRODUCTION' 
AND TABLE_NAME = 'CUSTOMERS_MASTER_DATA'
AND COLUMN_NAME IN ('CUSTOMER_ID', 'CUSTOMER_NAME', 'ACCOUNT_TYPE', 'SERVICE_ADDRESS', 'METER_ID')
ORDER BY ORDINAL_POSITION;

-- Check 4: Row count
SELECT 
    'CUSTOMERS_MASTER_DATA Data' AS check_name,
    (SELECT ROW_COUNT FROM INFORMATION_SCHEMA.TABLES 
     WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'CUSTOMERS_MASTER_DATA') AS row_count,
    CASE 
        WHEN (SELECT ROW_COUNT FROM INFORMATION_SCHEMA.TABLES 
              WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'CUSTOMERS_MASTER_DATA') > 0 
        THEN 'DATA LOADED'
        ELSE 'STRUCTURE ONLY'
    END AS data_status;

SELECT '====== STEP 5 VALIDATION COMPLETE ======' AS result,
       'Proceed to 06_ami_readings_pipeline.sql if all checks PASS' AS next_step;
