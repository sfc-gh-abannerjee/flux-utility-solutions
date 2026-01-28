-- =============================================================================
-- validate/07_validate_aggregations.sql
-- Validates: 07_aggregation_tables.sql
-- =============================================================================
-- Run after deploying 07_aggregation_tables.sql
-- Verifies: Aggregation and analytics tables
-- =============================================================================

USE DATABASE IDENTIFIER('{{ database }}');

SELECT '====== STEP 7 VALIDATION: AGGREGATION TABLES ======' AS validation;

-- Check 1: TRANSFORMER_HOURLY_LOAD table exists
SELECT 
    'TRANSFORMER_HOURLY_LOAD Table' AS check_name,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
     WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'TRANSFORMER_HOURLY_LOAD') AS table_exists,
    CASE 
        WHEN (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
              WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'TRANSFORMER_HOURLY_LOAD') = 1 
        THEN 'PASS' 
        ELSE 'FAIL' 
    END AS status;

-- Check 2: OUTAGE_EVENTS table exists
SELECT 
    'OUTAGE_EVENTS Table' AS check_name,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
     WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'OUTAGE_EVENTS') AS table_exists,
    CASE 
        WHEN (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
              WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'OUTAGE_EVENTS') = 1 
        THEN 'PASS' 
        ELSE 'FAIL' 
    END AS status;

-- Check 3: VOLTAGE_SAG_EVENTS table exists
SELECT 
    'VOLTAGE_SAG_EVENTS Table' AS check_name,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
     WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'VOLTAGE_SAG_EVENTS') AS table_exists,
    CASE 
        WHEN (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
              WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_NAME = 'VOLTAGE_SAG_EVENTS') = 1 
        THEN 'PASS' 
        ELSE 'FAIL' 
    END AS status;

-- Check 4: All aggregation table row counts
SELECT 
    TABLE_NAME,
    ROW_COUNT,
    CASE 
        WHEN ROW_COUNT > 0 THEN 'DATA LOADED'
        ELSE 'STRUCTURE ONLY'
    END AS data_status
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'PRODUCTION'
AND TABLE_NAME IN ('TRANSFORMER_HOURLY_LOAD', 'OUTAGE_EVENTS', 'VOLTAGE_SAG_EVENTS')
ORDER BY TABLE_NAME;

-- Check 5: TRANSFORMER_HOURLY_LOAD columns
SELECT 
    COLUMN_NAME,
    DATA_TYPE,
    'EXISTS' AS status
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'PRODUCTION' 
AND TABLE_NAME = 'TRANSFORMER_HOURLY_LOAD'
ORDER BY ORDINAL_POSITION;

SELECT '====== STEP 7 VALIDATION COMPLETE ======' AS result,
       'Proceed to 08_cortex_search.sql if all checks PASS' AS next_step;
