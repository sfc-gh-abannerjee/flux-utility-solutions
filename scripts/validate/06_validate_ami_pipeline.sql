-- =============================================================================
-- validate/06_validate_ami_pipeline.sql
-- Validates: 06_ami_readings_pipeline.sql
-- =============================================================================
-- Run after deploying 06_ami_readings_pipeline.sql
-- Verifies: AMI readings tables and streaming infrastructure
-- =============================================================================

USE DATABASE IDENTIFIER('{{ database }}');

SELECT '====== STEP 6 VALIDATION: AMI READINGS PIPELINE ======' AS validation;

-- Check 1: AMI_INTERVAL_READINGS table exists
SELECT 
    'AMI_INTERVAL_READINGS Table' AS check_name,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
     WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'AMI_INTERVAL_READINGS') AS table_exists,
    CASE 
        WHEN (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
              WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'AMI_INTERVAL_READINGS') = 1 
        THEN 'PASS' 
        ELSE 'FAIL' 
    END AS status;

-- Check 2: AMI_MONTHLY_USAGE table exists
SELECT 
    'AMI_MONTHLY_USAGE Table' AS check_name,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
     WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'AMI_MONTHLY_USAGE') AS table_exists,
    CASE 
        WHEN (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
              WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'AMI_MONTHLY_USAGE') = 1 
        THEN 'PASS' 
        ELSE 'FAIL' 
    END AS status;

-- Check 3: AMI_INTERVAL_READINGS columns
SELECT 
    'AMI_INTERVAL_READINGS Columns' AS check_name,
    COUNT(*) AS column_count,
    CASE WHEN COUNT(*) >= 5 THEN 'PASS' ELSE 'WARN' END AS status
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'AMI_INTERVAL_READINGS';

-- Check 4: Key columns for time-series data
SELECT 
    COLUMN_NAME,
    DATA_TYPE,
    'EXISTS' AS status
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'PRODUCTION' 
AND TABLE_NAME = 'AMI_INTERVAL_READINGS'
AND COLUMN_NAME IN ('METER_ID', 'TIMESTAMP', 'KWH_READING', 'VOLTAGE', 'QUALITY_FLAG')
ORDER BY ORDINAL_POSITION;

-- Check 5: Row counts for AMI tables
SELECT 
    TABLE_NAME,
    ROW_COUNT,
    CASE 
        WHEN ROW_COUNT > 0 THEN 'DATA LOADED'
        ELSE 'STRUCTURE ONLY'
    END AS data_status
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'PRODUCTION'
AND TABLE_NAME LIKE 'AMI%'
ORDER BY TABLE_NAME;

SELECT '====== STEP 6 VALIDATION COMPLETE ======' AS result,
       'Proceed to 07_aggregation_tables.sql if all checks PASS' AS next_step;
