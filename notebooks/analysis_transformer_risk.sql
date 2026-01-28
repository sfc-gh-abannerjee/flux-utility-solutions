-- =============================================================================
-- Flux Utility Solutions - Transformer Risk Analysis Notebook
-- =============================================================================
-- Analyze transformer fleet health, loading, and failure risk
-- Run in: Snowsight → Projects → Notebooks
-- =============================================================================

-- ## 1. Overview
-- 
-- This notebook analyzes transformer fleet risk:
-- - **Fleet Size**: 91,000 distribution transformers
-- - **Load Data**: 211 million hourly records
-- - **Coverage**: Summer peak periods
-- - **Goal**: Identify high-risk assets for proactive maintenance

-- ## 2. Setup

USE DATABASE SI_DEMOS;
USE SCHEMA PRODUCTION;
USE WAREHOUSE SI_DEMO_WH_LARGE;

-- ## 3. Fleet Overview
-- 
-- Understanding the transformer fleet composition.

-- Fleet summary
SELECT 
    COUNT(*) AS TOTAL_TRANSFORMERS,
    AVG(AGE_YEARS) AS AVG_AGE,
    AVG(HEALTH_SCORE) AS AVG_HEALTH,
    SUM(RATED_KVA) / 1000 AS TOTAL_CAPACITY_MVA,
    SUM(METER_COUNT) AS TOTAL_METERS_SERVED
FROM TRANSFORMER_METADATA;

-- Distribution by role
SELECT 
    TRANSFORMER_ROLE,
    COUNT(*) AS COUNT,
    AVG(RATED_KVA) AS AVG_KVA,
    AVG(AGE_YEARS) AS AVG_AGE
FROM TRANSFORMER_METADATA
GROUP BY 1
ORDER BY COUNT DESC;

-- ## 4. Health Score Distribution
-- 
-- Analyze health score distribution across the fleet.

-- Health score buckets
SELECT 
    CASE 
        WHEN HEALTH_SCORE >= 80 THEN 'EXCELLENT (80-100)'
        WHEN HEALTH_SCORE >= 60 THEN 'GOOD (60-79)'
        WHEN HEALTH_SCORE >= 40 THEN 'FAIR (40-59)'
        WHEN HEALTH_SCORE >= 20 THEN 'POOR (20-39)'
        ELSE 'CRITICAL (<20)'
    END AS HEALTH_CATEGORY,
    COUNT(*) AS TRANSFORMER_COUNT,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS PERCENTAGE
FROM TRANSFORMER_METADATA
GROUP BY 1
ORDER BY PERCENTAGE DESC;

-- Low health transformers by area
SELECT 
    LOCATION_AREA,
    COUNT(*) AS TOTAL,
    COUNT_IF(HEALTH_SCORE < 50) AS LOW_HEALTH,
    ROUND(COUNT_IF(HEALTH_SCORE < 50) * 100.0 / COUNT(*), 2) AS LOW_HEALTH_PCT
FROM TRANSFORMER_METADATA
GROUP BY 1
ORDER BY LOW_HEALTH DESC
LIMIT 10;

-- ## 5. Age Analysis
-- 
-- Analyze transformer age distribution and its relationship to health.

-- Age distribution
SELECT 
    CASE 
        WHEN AGE_YEARS < 10 THEN '< 10 years'
        WHEN AGE_YEARS < 20 THEN '10-19 years'
        WHEN AGE_YEARS < 30 THEN '20-29 years'
        WHEN AGE_YEARS < 40 THEN '30-39 years'
        ELSE '40+ years'
    END AS AGE_BUCKET,
    COUNT(*) AS COUNT,
    AVG(HEALTH_SCORE) AS AVG_HEALTH
FROM TRANSFORMER_METADATA
GROUP BY 1
ORDER BY COUNT DESC;

-- Aging transformers (over 35 years)
SELECT 
    COUNT(*) AS AGING_TRANSFORMERS,
    AVG(HEALTH_SCORE) AS AVG_HEALTH,
    SUM(METER_COUNT) AS CUSTOMERS_AT_RISK
FROM TRANSFORMER_METADATA
WHERE AGE_YEARS > 35;

-- ## 6. Loading Analysis
-- 
-- Analyze transformer loading patterns.

-- Loading distribution from hourly data
SELECT 
    CASE 
        WHEN LOAD_FACTOR_PCT < 50 THEN 'LOW (<50%)'
        WHEN LOAD_FACTOR_PCT < 80 THEN 'MODERATE (50-80%)'
        WHEN LOAD_FACTOR_PCT < 100 THEN 'HIGH (80-100%)'
        ELSE 'OVERLOADED (>100%)'
    END AS LOADING_CATEGORY,
    COUNT(*) AS HOUR_COUNT,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS PERCENTAGE
FROM TRANSFORMER_HOURLY_LOAD
GROUP BY 1
ORDER BY PERCENTAGE DESC;

-- Most frequently overloaded transformers
SELECT 
    TRANSFORMER_ID,
    COUNT(*) AS TOTAL_HOURS,
    SUM(CASE WHEN IS_OVERLOADED THEN 1 ELSE 0 END) AS OVERLOAD_HOURS,
    ROUND(SUM(CASE WHEN IS_OVERLOADED THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS OVERLOAD_PCT,
    MAX(LOAD_FACTOR_PCT) AS PEAK_LOAD_PCT
FROM TRANSFORMER_HOURLY_LOAD
GROUP BY 1
HAVING OVERLOAD_HOURS > 10
ORDER BY OVERLOAD_HOURS DESC
LIMIT 20;

-- ## 7. Thermal Stress Analysis
-- 
-- Analyze thermal stress categories and accumulation.

-- Stress distribution
SELECT 
    THERMAL_STRESS_CATEGORY,
    COUNT(*) AS HOUR_COUNT,
    COUNT(DISTINCT TRANSFORMER_ID) AS TRANSFORMERS_AFFECTED
FROM TRANSFORMER_HOURLY_LOAD
GROUP BY 1
ORDER BY HOUR_COUNT DESC;

-- Critical stress hours by transformer
SELECT 
    TRANSFORMER_ID,
    SUM(CASE WHEN THERMAL_STRESS_CATEGORY = 'CRITICAL' THEN 1 ELSE 0 END) AS CRITICAL_HOURS,
    SUM(CASE WHEN THERMAL_STRESS_CATEGORY = 'HIGH' THEN 1 ELSE 0 END) AS HIGH_HOURS,
    AVG(LOAD_FACTOR_PCT) AS AVG_LOAD_PCT
FROM TRANSFORMER_HOURLY_LOAD
GROUP BY 1
HAVING CRITICAL_HOURS > 0
ORDER BY CRITICAL_HOURS DESC
LIMIT 20;

-- ## 8. Combined Risk Score
-- 
-- Calculate combined risk score based on multiple factors.

-- High-risk transformers (multi-factor)
SELECT 
    t.TRANSFORMER_ID,
    t.LOCATION_AREA,
    t.AGE_YEARS,
    t.HEALTH_SCORE,
    t.METER_COUNT AS CUSTOMERS,
    h.AVG_LOAD_PCT,
    h.PEAK_LOAD_PCT,
    h.OVERLOAD_HOURS,
    h.CRITICAL_STRESS_HOURS,
    -- Risk Score (higher = more risk)
    ROUND(
        (100 - t.HEALTH_SCORE) * 0.3 +  -- 30% health
        (t.AGE_YEARS / 50 * 100) * 0.2 +  -- 20% age
        LEAST(h.AVG_LOAD_PCT, 150) * 0.25 +  -- 25% avg load
        LEAST(h.OVERLOAD_HOURS, 100) * 0.15 +  -- 15% overload frequency
        LEAST(h.CRITICAL_STRESS_HOURS, 50) * 0.1  -- 10% critical stress
    , 2) AS RISK_SCORE
FROM TRANSFORMER_METADATA t
JOIN (
    SELECT 
        TRANSFORMER_ID,
        AVG(LOAD_FACTOR_PCT) AS AVG_LOAD_PCT,
        MAX(LOAD_FACTOR_PCT) AS PEAK_LOAD_PCT,
        SUM(CASE WHEN IS_OVERLOADED THEN 1 ELSE 0 END) AS OVERLOAD_HOURS,
        SUM(CASE WHEN THERMAL_STRESS_CATEGORY = 'CRITICAL' THEN 1 ELSE 0 END) AS CRITICAL_STRESS_HOURS
    FROM TRANSFORMER_HOURLY_LOAD
    GROUP BY 1
) h ON t.TRANSFORMER_ID = h.TRANSFORMER_ID
WHERE t.HEALTH_SCORE < 60 
   OR h.OVERLOAD_HOURS > 20
   OR t.AGE_YEARS > 35
ORDER BY RISK_SCORE DESC
LIMIT 50;

-- ## 9. Geographic Risk Concentration
-- 
-- Identify areas with highest risk concentration.

SELECT 
    t.LOCATION_AREA,
    COUNT(*) AS TRANSFORMER_COUNT,
    AVG(t.HEALTH_SCORE) AS AVG_HEALTH,
    AVG(t.AGE_YEARS) AS AVG_AGE,
    SUM(t.METER_COUNT) AS TOTAL_CUSTOMERS,
    COUNT_IF(t.HEALTH_SCORE < 50) AS LOW_HEALTH_COUNT,
    COUNT_IF(t.AGE_YEARS > 35) AS AGING_COUNT
FROM TRANSFORMER_METADATA t
GROUP BY 1
ORDER BY LOW_HEALTH_COUNT DESC
LIMIT 10;

-- ## 10. Replacement Priority List
-- 
-- Generate prioritized replacement list.

SELECT 
    t.TRANSFORMER_ID,
    t.LOCATION_AREA,
    t.SUBSTATION_ID,
    t.RATED_KVA,
    t.AGE_YEARS,
    t.HEALTH_SCORE,
    t.METER_COUNT,
    CASE 
        WHEN t.HEALTH_SCORE < 30 AND t.AGE_YEARS > 35 THEN 'URGENT'
        WHEN t.HEALTH_SCORE < 50 OR t.AGE_YEARS > 40 THEN 'HIGH'
        WHEN t.HEALTH_SCORE < 70 AND t.AGE_YEARS > 30 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS REPLACEMENT_PRIORITY
FROM TRANSFORMER_METADATA t
WHERE t.HEALTH_SCORE < 70 OR t.AGE_YEARS > 35
ORDER BY 
    CASE REPLACEMENT_PRIORITY 
        WHEN 'URGENT' THEN 1 
        WHEN 'HIGH' THEN 2 
        WHEN 'MEDIUM' THEN 3 
        ELSE 4 
    END,
    t.HEALTH_SCORE ASC
LIMIT 100;

-- ## 11. Summary
-- 
-- Key findings:
-- - Fleet: 91K transformers, average age [X] years
-- - At-risk: [Y] transformers with health < 50
-- - Overloading: [Z] transformers frequently overloaded
-- - Recommendations: See replacement priority list

SELECT 
    'Transformer Risk Analysis Complete' AS STATUS,
    COUNT(*) AS TOTAL_TRANSFORMERS,
    COUNT_IF(HEALTH_SCORE < 50) AS HIGH_RISK_COUNT,
    COUNT_IF(AGE_YEARS > 35) AS AGING_COUNT
FROM TRANSFORMER_METADATA;
