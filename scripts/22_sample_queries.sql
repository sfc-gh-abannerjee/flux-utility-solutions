-- ============================================================================
-- Flux Utility Solutions: Sample Queries
-- ============================================================================
-- Script: 22_sample_queries.sql
-- Purpose: Example queries demonstrating Snowflake capabilities with utility data
--
-- Categories:
-- 1. Basic Analytics
-- 2. Geospatial Queries
-- 3. Time Series Analysis
-- 4. Cortex AI Integration
-- 5. Performance Patterns
-- ============================================================================

-- ============================================================================
-- 1. BASIC ANALYTICS
-- ============================================================================

-- Grid overview statistics
SELECT 
    (SELECT COUNT(*) FROM SUBSTATIONS) as substations,
    (SELECT COUNT(*) FROM TRANSFORMER_METADATA) as transformers,
    (SELECT COUNT(*) FROM CUSTOMERS_MASTER_DATA) as customers,
    (SELECT COUNT(*) FROM METER_INFRASTRUCTURE) as meters,
    (SELECT COUNT(*) FROM AMI_INTERVAL_READINGS) as ami_readings;

-- Transformer health distribution
SELECT 
    CASE 
        WHEN health_score >= 90 THEN 'Excellent (90-100)'
        WHEN health_score >= 70 THEN 'Good (70-89)'
        WHEN health_score >= 50 THEN 'Fair (50-69)'
        ELSE 'Poor (<50)'
    END as health_category,
    COUNT(*) as transformer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM TRANSFORMER_METADATA
GROUP BY 1
ORDER BY 
    CASE health_category
        WHEN 'Excellent (90-100)' THEN 1
        WHEN 'Good (70-89)' THEN 2
        WHEN 'Fair (50-69)' THEN 3
        ELSE 4
    END;

-- Customer distribution by rate class
SELECT 
    rate_class,
    COUNT(*) as customer_count,
    COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () as pct
FROM CUSTOMERS_MASTER_DATA
GROUP BY rate_class
ORDER BY customer_count DESC;

-- ============================================================================
-- 2. GEOSPATIAL QUERIES
-- ============================================================================

-- Find substations within 10km of downtown Houston
SELECT 
    substation_id,
    substation_name,
    capacity_mva,
    ST_DISTANCE(
        location,
        ST_MAKEPOINT(-95.3698, 29.7604)  -- Downtown Houston
    ) / 1000 as distance_km
FROM SUBSTATIONS
WHERE ST_DISTANCE(
    location,
    ST_MAKEPOINT(-95.3698, 29.7604)
) <= 10000
ORDER BY distance_km;

-- Find transformers in a bounding box
SELECT 
    transformer_id,
    substation_id,
    health_score,
    ST_X(location) as longitude,
    ST_Y(location) as latitude
FROM TRANSFORMER_METADATA
WHERE ST_WITHIN(
    location,
    ST_MAKEENVELOPE(-95.5, 29.6, -95.2, 29.9)  -- Houston area
)
LIMIT 100;

-- Customers per substation service area (using nearest substation)
SELECT 
    s.substation_id,
    s.substation_name,
    COUNT(DISTINCT c.customer_id) as customer_count
FROM SUBSTATIONS s
JOIN TRANSFORMER_METADATA t ON s.substation_id = t.substation_id
JOIN METER_INFRASTRUCTURE m ON t.transformer_id = m.transformer_id
JOIN CUSTOMERS_MASTER_DATA c ON m.customer_id = c.customer_id
GROUP BY s.substation_id, s.substation_name
ORDER BY customer_count DESC
LIMIT 20;

-- ============================================================================
-- 3. TIME SERIES ANALYSIS
-- ============================================================================

-- Hourly load profile (last 7 days)
SELECT 
    DATE_TRUNC('hour', reading_timestamp) as hour,
    SUM(kwh_reading) as total_kwh,
    AVG(kwh_reading) as avg_kwh,
    COUNT(DISTINCT meter_id) as active_meters
FROM AMI_INTERVAL_READINGS
WHERE reading_timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1;

-- Peak demand by day of week
SELECT 
    DAYNAME(reading_timestamp) as day_of_week,
    DAYOFWEEK(reading_timestamp) as day_num,
    MAX(kwh_reading) as peak_kwh,
    AVG(kwh_reading) as avg_kwh
FROM AMI_INTERVAL_READINGS
WHERE reading_timestamp >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY day_num;

-- Transformer load patterns over 24 hours
SELECT 
    HOUR(reading_timestamp) as hour_of_day,
    AVG(kwh_reading) as avg_load,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY kwh_reading) as p95_load,
    MAX(kwh_reading) as max_load
FROM AMI_INTERVAL_READINGS a
JOIN METER_INFRASTRUCTURE m ON a.meter_id = m.meter_id
WHERE a.reading_timestamp >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1;

-- ============================================================================
-- 4. CORTEX AI INTEGRATION
-- ============================================================================

-- Generate transformer inspection summary using LLM
SELECT 
    transformer_id,
    health_score,
    installation_date,
    DATEDIFF(year, installation_date, CURRENT_DATE()) as age_years,
    SNOWFLAKE.CORTEX.COMPLETE(
        'mistral-large2',
        'Summarize the maintenance priority for a transformer with health score ' || 
        health_score || ' and age ' || 
        DATEDIFF(year, installation_date, CURRENT_DATE()) || 
        ' years. Respond in one sentence.'
    ) as ai_recommendation
FROM TRANSFORMER_METADATA
WHERE health_score < 70
ORDER BY health_score
LIMIT 5;

-- Semantic search for customer issues (requires Cortex Search service)
-- SELECT * FROM TABLE(
--     SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
--         'customer_service_search',
--         'billing dispute high energy usage',
--         {'limit': 10}
--     )
-- );

-- Sentiment analysis on customer feedback
SELECT 
    customer_id,
    feedback_text,
    SNOWFLAKE.CORTEX.SENTIMENT(feedback_text) as sentiment_score,
    CASE 
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(feedback_text) > 0.5 THEN 'Positive'
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(feedback_text) < -0.5 THEN 'Negative'
        ELSE 'Neutral'
    END as sentiment_category
FROM CUSTOMER_FEEDBACK
LIMIT 10;

-- ============================================================================
-- 5. PERFORMANCE PATTERNS
-- ============================================================================

-- Using clustering for faster scans on large tables
ALTER TABLE AMI_INTERVAL_READINGS CLUSTER BY (reading_timestamp, transformer_id);

-- Query using cluster keys (will use pruning)
SELECT 
    transformer_id,
    DATE_TRUNC('day', reading_timestamp) as day,
    SUM(kwh_reading) as daily_kwh
FROM AMI_INTERVAL_READINGS
WHERE reading_timestamp BETWEEN '2024-01-01' AND '2024-01-31'
  AND transformer_id LIKE 'TRF-001%'
GROUP BY 1, 2
ORDER BY 1, 2;

-- Efficient aggregation with APPROX functions on 7B rows
SELECT 
    DATE_TRUNC('month', reading_timestamp) as month,
    APPROX_COUNT_DISTINCT(meter_id) as unique_meters,
    APPROX_PERCENTILE(kwh_reading, 0.5) as median_kwh,
    APPROX_PERCENTILE(kwh_reading, 0.95) as p95_kwh
FROM AMI_INTERVAL_READINGS
WHERE reading_timestamp >= '2024-01-01'
GROUP BY 1
ORDER BY 1;

-- Using result caching (same query returns instantly)
SELECT COUNT(*) as total_readings FROM AMI_INTERVAL_READINGS;
-- Run again - uses cached result

-- ============================================================================
-- 6. ADVANCED ANALYTICS
-- ============================================================================

-- Rolling 7-day average consumption per transformer
SELECT 
    transformer_id,
    reading_date,
    daily_kwh,
    AVG(daily_kwh) OVER (
        PARTITION BY transformer_id 
        ORDER BY reading_date 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) as rolling_7day_avg
FROM (
    SELECT 
        transformer_id,
        DATE(reading_timestamp) as reading_date,
        SUM(kwh_reading) as daily_kwh
    FROM AMI_INTERVAL_READINGS
    WHERE reading_timestamp >= DATEADD(day, -30, CURRENT_TIMESTAMP())
    GROUP BY 1, 2
)
ORDER BY transformer_id, reading_date;

-- Anomaly detection using statistical methods
WITH stats AS (
    SELECT 
        transformer_id,
        AVG(kwh_reading) as mean_kwh,
        STDDEV(kwh_reading) as stddev_kwh
    FROM AMI_INTERVAL_READINGS
    WHERE reading_timestamp >= DATEADD(day, -30, CURRENT_TIMESTAMP())
    GROUP BY transformer_id
)
SELECT 
    a.meter_id,
    a.transformer_id,
    a.reading_timestamp,
    a.kwh_reading,
    s.mean_kwh,
    (a.kwh_reading - s.mean_kwh) / NULLIF(s.stddev_kwh, 0) as z_score
FROM AMI_INTERVAL_READINGS a
JOIN stats s ON a.transformer_id = s.transformer_id
WHERE a.reading_timestamp >= DATEADD(day, -1, CURRENT_TIMESTAMP())
  AND ABS((a.kwh_reading - s.mean_kwh) / NULLIF(s.stddev_kwh, 0)) > 3
ORDER BY z_score DESC
LIMIT 100;

-- Customer segmentation by usage pattern
SELECT 
    customer_id,
    avg_daily_kwh,
    peak_hour,
    CASE 
        WHEN avg_daily_kwh > 50 AND peak_hour BETWEEN 17 AND 21 THEN 'High-Evening'
        WHEN avg_daily_kwh > 50 AND peak_hour BETWEEN 9 AND 17 THEN 'High-Daytime'
        WHEN avg_daily_kwh <= 20 THEN 'Low-Usage'
        ELSE 'Medium-Mixed'
    END as usage_segment
FROM (
    SELECT 
        c.customer_id,
        AVG(a.kwh_reading * 96) as avg_daily_kwh,  -- 96 intervals per day
        MODE(HOUR(a.reading_timestamp)) as peak_hour
    FROM CUSTOMERS_MASTER_DATA c
    JOIN METER_INFRASTRUCTURE m ON c.customer_id = m.customer_id
    JOIN AMI_INTERVAL_READINGS a ON m.meter_id = a.meter_id
    WHERE a.reading_timestamp >= DATEADD(day, -30, CURRENT_TIMESTAMP())
    GROUP BY c.customer_id
)
LIMIT 1000;

-- ============================================================================
-- End of Sample Queries
-- ============================================================================
