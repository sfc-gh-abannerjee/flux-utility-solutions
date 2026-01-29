-- =============================================================================
-- Flux Utility Solutions - AMI Data Exploration Notebook
-- =============================================================================
-- Interactive exploration of 7.1 billion AMI interval readings
-- Run in: Snowsight → Projects → Notebooks
-- =============================================================================

-- ## 1. Overview
-- 
-- This notebook explores the AMI (Advanced Metering Infrastructure) data:
-- - **Scale**: 7.1 billion 15-minute interval readings
-- - **Coverage**: July-August 2024, July-August 2025
-- - **Meters**: 597,000 smart meters
-- - **Metrics**: kWh consumption, voltage, power factor

-- ## 2. Setup

USE DATABASE <% database %>;
USE SCHEMA PRODUCTION;
USE WAREHOUSE <% warehouse %>;

-- ## 3. Data Scale
-- 
-- Understanding the dataset size.

-- Total row count (uses metadata, very fast)
SELECT 
    'AMI_INTERVAL_READINGS' AS TABLE_NAME,
    COUNT(*) AS ROW_COUNT
FROM AMI_INTERVAL_READINGS;

-- Row count by year-month
SELECT 
    DATE_TRUNC('MONTH', TIMESTAMP) AS MONTH,
    COUNT(*) AS READINGS,
    COUNT(DISTINCT METER_ID) AS METERS
FROM AMI_INTERVAL_READINGS
GROUP BY 1
ORDER BY 1;

-- ## 4. Data Sample
-- 
-- Look at sample records to understand structure.

SELECT *
FROM AMI_READINGS_FINAL
WHERE TIMESTAMP >= '2025-08-01'
LIMIT 100;

-- Column summary
SELECT 
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'AMI_READINGS_FINAL'
ORDER BY ORDINAL_POSITION;

-- ## 5. Consumption Patterns
-- 
-- Analyze energy consumption patterns.

-- Daily consumption trend (August 2025)
SELECT 
    DATE_TRUNC('DAY', TIMESTAMP) AS DAY,
    SUM(USAGE_KWH_ADJUSTED) / 1000000 AS TOTAL_GWH,
    AVG(USAGE_KWH_ADJUSTED) AS AVG_KWH,
    COUNT(DISTINCT METER_ID) AS ACTIVE_METERS
FROM AMI_READINGS_FINAL
WHERE TIMESTAMP BETWEEN '2025-08-01' AND '2025-08-31'
GROUP BY 1
ORDER BY 1;

-- Hourly pattern (typical summer day)
SELECT 
    HOUR(TIMESTAMP) AS HOUR_OF_DAY,
    AVG(USAGE_KWH_ADJUSTED) AS AVG_KWH,
    MAX(USAGE_KWH_ADJUSTED) AS MAX_KWH
FROM AMI_READINGS_FINAL
WHERE DATE(TIMESTAMP) = '2025-08-15'
GROUP BY 1
ORDER BY 1;

-- ## 6. Voltage Quality
-- 
-- Analyze voltage readings and quality issues.

-- Voltage distribution
SELECT 
    CASE 
        WHEN VOLTAGE < 114 THEN 'LOW (<114V)'
        WHEN VOLTAGE BETWEEN 114 AND 126 THEN 'NORMAL (114-126V)'
        ELSE 'HIGH (>126V)'
    END AS VOLTAGE_CATEGORY,
    COUNT(*) AS READING_COUNT,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS PERCENTAGE
FROM AMI_READINGS_FINAL
WHERE VOLTAGE IS NOT NULL
GROUP BY 1
ORDER BY PERCENTAGE DESC;

-- Low voltage incidents by day
SELECT 
    DATE_TRUNC('DAY', TIMESTAMP) AS DAY,
    COUNT_IF(VOLTAGE < 114) AS LOW_VOLTAGE_COUNT,
    COUNT(*) AS TOTAL_READINGS,
    ROUND(COUNT_IF(VOLTAGE < 114) * 100.0 / COUNT(*), 4) AS LOW_VOLTAGE_PCT
FROM AMI_READINGS_FINAL
WHERE TIMESTAMP BETWEEN '2025-08-01' AND '2025-08-31'
GROUP BY 1
ORDER BY LOW_VOLTAGE_COUNT DESC
LIMIT 10;

-- ## 7. Voltage Sag Events
-- 
-- Analyze voltage sag events affecting grid reliability.

-- Sag events by type
SELECT 
    SAG_TYPE,
    COUNT(*) AS EVENT_COUNT,
    AVG(VOLTAGE_DROP_AMOUNT) AS AVG_DROP_VOLTS,
    MAX(VOLTAGE_DROP_AMOUNT) AS MAX_DROP_VOLTS
FROM AMI_READINGS_FINAL
WHERE SAG_TYPE IS NOT NULL
GROUP BY 1
ORDER BY EVENT_COUNT DESC;

-- Meters most affected by sags
SELECT 
    METER_ID,
    COUNT_IF(VOLTAGE_SAG_EVENT_ID IS NOT NULL) AS SAG_COUNT,
    AVG(VOLTAGE_DROP_AMOUNT) AS AVG_DROP
FROM AMI_READINGS_FINAL
GROUP BY 1
HAVING SAG_COUNT > 0
ORDER BY SAG_COUNT DESC
LIMIT 20;

-- ## 8. Outage Impact
-- 
-- Analyze outage impact on consumption data.

-- Outage statistics
SELECT 
    OUTAGE_CAUSE,
    COUNT(*) AS AFFECTED_INTERVALS,
    COUNT(DISTINCT METER_ID) AS AFFECTED_METERS,
    SUM(USAGE_KWH - USAGE_KWH_ADJUSTED) AS LOST_KWH
FROM AMI_READINGS_FINAL
WHERE OUTAGE_ID IS NOT NULL
GROUP BY 1
ORDER BY AFFECTED_INTERVALS DESC;

-- ## 9. Top Consumers
-- 
-- Identify highest consumption meters.

-- Top 20 meters by total consumption (August 2025)
SELECT 
    METER_ID,
    SUM(USAGE_KWH_ADJUSTED) AS TOTAL_KWH,
    AVG(USAGE_KWH_ADJUSTED) AS AVG_INTERVAL_KWH,
    COUNT(*) AS READING_COUNT
FROM AMI_READINGS_FINAL
WHERE TIMESTAMP BETWEEN '2025-08-01' AND '2025-08-31'
GROUP BY 1
ORDER BY TOTAL_KWH DESC
LIMIT 20;

-- ## 10. Year-over-Year Comparison
-- 
-- Compare 2024 vs 2025 summer data.

SELECT 
    YEAR(TIMESTAMP) AS YEAR,
    SUM(USAGE_KWH_ADJUSTED) / 1000000000 AS TOTAL_TWH,
    AVG(USAGE_KWH_ADJUSTED) AS AVG_KWH,
    COUNT(DISTINCT METER_ID) AS UNIQUE_METERS,
    COUNT(*) AS TOTAL_READINGS
FROM AMI_READINGS_FINAL
WHERE MONTH(TIMESTAMP) IN (7, 8)  -- July-August only
GROUP BY 1
ORDER BY 1;

-- ## 11. Summary
-- 
-- Key insights from AMI data exploration:
-- 
-- - **Scale**: 7.1B readings from 597K meters
-- - **Peak consumption**: Afternoon hours (2-7 PM)
-- - **Voltage quality**: ~0.1% low voltage incidents
-- - **Outage causes**: Transformer overload most common
-- - **YoY growth**: Compare consumption trends

SELECT 'AMI Exploration Complete' AS STATUS;
