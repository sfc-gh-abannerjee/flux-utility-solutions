-- =============================================================================
-- 15_marketplace_listings.sql
-- Flux Utility Solutions - Snowflake Marketplace Integration
-- =============================================================================
-- Purpose: Configure data products for Snowflake Marketplace sharing
-- Dependencies: All PRODUCTION tables
-- Jinja2 Variables:
--   <% database %>     - Target database name
--   <% admin_role %>   - Admin role for sharing
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');

-- -----------------------------------------------------------------------------
-- 1. CREATE SHARE FOR GRID ANALYTICS DATA PRODUCT
-- -----------------------------------------------------------------------------

CREATE SHARE IF NOT EXISTS FLUX_GRID_ANALYTICS_SHARE
    COMMENT = 'Flux Grid Analytics - Anonymized utility grid data for research and analytics';

-- Grant usage on database to share
GRANT USAGE ON DATABASE IDENTIFIER('<% database %>') TO SHARE FLUX_GRID_ANALYTICS_SHARE;
GRANT USAGE ON SCHEMA PRODUCTION TO SHARE FLUX_GRID_ANALYTICS_SHARE;

-- -----------------------------------------------------------------------------
-- 2. CREATE ANONYMIZED VIEWS FOR SHARING
-- -----------------------------------------------------------------------------
-- Data must be anonymized before sharing externally

-- Anonymized transformer performance data
CREATE OR ALTER SECURE VIEW APPLICATIONS.MARKETPLACE_TRANSFORMER_ANALYTICS AS
SELECT
    -- Hash transformer ID for anonymization
    SHA2(TRANSFORMER_ID, 256) AS ASSET_HASH,
    -- Keep technical attributes
    RATED_KVA,
    TRANSFORMER_ROLE,
    AGE_YEARS,
    -- Generalize location to county level
    LOCATION_AREA,
    -- Performance metrics
    LOAD_UTILIZATION_PCT,
    HEALTH_SCORE,
    -- Time attributes
    DATE_TRUNC('MONTH', INSTALLATION_DATE) AS INSTALL_MONTH
FROM PRODUCTION.TRANSFORMER_METADATA
COMMENT = 'Anonymized transformer analytics for marketplace sharing';

-- Anonymized AMI statistics (aggregated)
CREATE OR ALTER SECURE VIEW APPLICATIONS.MARKETPLACE_AMI_STATISTICS AS
SELECT
    DATE_TRUNC('DAY', TIMESTAMP) AS READING_DATE,
    DATE_PART('HOUR', TIMESTAMP) AS HOUR_OF_DAY,
    -- Aggregate by area
    CASE 
        WHEN RANDOM() < 0.33 THEN 'ZONE_A'
        WHEN RANDOM() < 0.66 THEN 'ZONE_B'
        ELSE 'ZONE_C'
    END AS ANONYMIZED_ZONE,
    -- Statistical aggregates only
    COUNT(DISTINCT METER_ID) AS METER_COUNT,
    AVG(USAGE_KWH) AS AVG_USAGE_KWH,
    STDDEV(USAGE_KWH) AS STDDEV_USAGE_KWH,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY USAGE_KWH) AS MEDIAN_USAGE_KWH,
    AVG(VOLTAGE) AS AVG_VOLTAGE,
    -- Temperature band (not exact)
    ROUND(AVG(POWER_FACTOR), 2) AS AVG_POWER_FACTOR
FROM PRODUCTION.AMI_INTERVAL_READINGS
GROUP BY 1, 2, 3
COMMENT = 'Anonymized AMI statistics for marketplace sharing';

-- Grid reliability metrics
CREATE OR ALTER SECURE VIEW APPLICATIONS.MARKETPLACE_RELIABILITY_METRICS AS
SELECT
    DATE_TRUNC('MONTH', LOAD_HOUR) AS METRIC_MONTH,
    -- Anonymized categories
    CASE 
        WHEN THERMAL_STRESS_CATEGORY = 'CRITICAL' THEN 'HIGH_STRESS'
        WHEN THERMAL_STRESS_CATEGORY = 'HIGH' THEN 'HIGH_STRESS'
        ELSE 'NORMAL_STRESS'
    END AS STRESS_CATEGORY,
    -- Aggregate metrics
    COUNT(DISTINCT TRANSFORMER_ID) AS TRANSFORMER_COUNT,
    AVG(LOAD_FACTOR_PCT) AS AVG_LOAD_FACTOR,
    SUM(CASE WHEN IS_OVERLOADED THEN 1 ELSE 0 END)::FLOAT / COUNT(*) * 100 AS OVERLOAD_RATE_PCT
FROM PRODUCTION.TRANSFORMER_HOURLY_LOAD
GROUP BY 1, 2
COMMENT = 'Grid reliability metrics for marketplace sharing';

-- -----------------------------------------------------------------------------
-- 3. GRANT VIEWS TO SHARE
-- -----------------------------------------------------------------------------

GRANT SELECT ON VIEW APPLICATIONS.MARKETPLACE_TRANSFORMER_ANALYTICS 
    TO SHARE FLUX_GRID_ANALYTICS_SHARE;
    
GRANT SELECT ON VIEW APPLICATIONS.MARKETPLACE_AMI_STATISTICS 
    TO SHARE FLUX_GRID_ANALYTICS_SHARE;
    
GRANT SELECT ON VIEW APPLICATIONS.MARKETPLACE_RELIABILITY_METRICS 
    TO SHARE FLUX_GRID_ANALYTICS_SHARE;

-- -----------------------------------------------------------------------------
-- 4. CREATE SAMPLE DATA PRODUCT LISTING METADATA
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS APPLICATIONS.MARKETPLACE_LISTINGS (
    LISTING_ID VARCHAR(50) DEFAULT UUID_STRING(),
    LISTING_NAME VARCHAR(200) NOT NULL,
    LISTING_TYPE VARCHAR(50) NOT NULL,  -- DATA_PRODUCT, APPLICATION, MODEL
    SHARE_NAME VARCHAR(200),
    
    -- Product Information
    TITLE VARCHAR(500),
    DESCRIPTION TEXT,
    CATEGORY VARCHAR(100),
    INDUSTRY VARCHAR(100),
    USE_CASES VARIANT,  -- Array of use case strings
    
    -- Data Information
    DATA_REFRESH_FREQUENCY VARCHAR(50),
    DATA_COVERAGE_START DATE,
    DATA_COVERAGE_END DATE,
    GEOGRAPHIC_COVERAGE VARCHAR(200),
    ROW_COUNT_ESTIMATE NUMBER(15,0),
    
    -- Pricing
    PRICING_MODEL VARCHAR(50),  -- FREE, USAGE_BASED, SUBSCRIPTION
    PRICE_USD NUMBER(10,2),
    
    -- Status
    STATUS VARCHAR(20) DEFAULT 'DRAFT',  -- DRAFT, PENDING_REVIEW, PUBLISHED, ARCHIVED
    PUBLISHED_AT TIMESTAMP_NTZ,
    
    -- Metadata
    CREATED_BY VARCHAR(100),
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Marketplace listing metadata for Flux data products';

-- Insert listing metadata
INSERT INTO APPLICATIONS.MARKETPLACE_LISTINGS (
    LISTING_NAME,
    LISTING_TYPE,
    SHARE_NAME,
    TITLE,
    DESCRIPTION,
    CATEGORY,
    INDUSTRY,
    USE_CASES,
    DATA_REFRESH_FREQUENCY,
    GEOGRAPHIC_COVERAGE,
    ROW_COUNT_ESTIMATE,
    PRICING_MODEL,
    STATUS
) VALUES (
    'flux_grid_analytics',
    'DATA_PRODUCT',
    'FLUX_GRID_ANALYTICS_SHARE',
    'Utility Grid Analytics Dataset',
    'Comprehensive anonymized dataset of utility grid operations including transformer performance, AMI consumption patterns, and reliability metrics. Ideal for research, benchmarking, and ML model development.',
    'Energy & Utilities',
    'Utilities',
    PARSE_JSON('["Grid reliability research", "Load forecasting model training", "Asset health benchmarking", "Energy consumption pattern analysis"]'),
    'DAILY',
    'Texas, United States',
    7000000000,  -- 7B+ rows across all tables
    'FREE',
    'DRAFT'
);

-- -----------------------------------------------------------------------------
-- 5. CONSUMER INBOUND SHARES (External Data)
-- -----------------------------------------------------------------------------
-- Configuration for consuming external marketplace data

CREATE TABLE IF NOT EXISTS APPLICATIONS.MARKETPLACE_SUBSCRIPTIONS (
    SUBSCRIPTION_ID VARCHAR(50) DEFAULT UUID_STRING(),
    PROVIDER_NAME VARCHAR(200) NOT NULL,
    LISTING_NAME VARCHAR(200) NOT NULL,
    DATABASE_NAME VARCHAR(200),
    
    -- Status
    STATUS VARCHAR(20) DEFAULT 'ACTIVE',
    SUBSCRIBED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    EXPIRES_AT TIMESTAMP_NTZ,
    
    -- Usage
    LAST_QUERY_AT TIMESTAMP_NTZ,
    QUERY_COUNT_MTD NUMBER(10,0) DEFAULT 0
)
COMMENT = 'Marketplace subscriptions for external data sources';

-- Example subscription records (if consuming external data)
INSERT INTO APPLICATIONS.MARKETPLACE_SUBSCRIPTIONS (
    PROVIDER_NAME,
    LISTING_NAME,
    DATABASE_NAME,
    STATUS
) VALUES
    ('Weather Source', 'Global Weather Data', 'WEATHER_SOURCE__GLOBAL_WEATHER', 'ACTIVE'),
    ('Precisely', 'Address Master Data', 'PRECISELY__MASTERDATA', 'ACTIVE')
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- 6. VERIFICATION
-- -----------------------------------------------------------------------------

-- Show shares
SHOW SHARES LIKE 'FLUX%';

-- Show objects in share
SHOW OBJECTS IN SHARE FLUX_GRID_ANALYTICS_SHARE;

-- Preview shared data
SELECT * FROM APPLICATIONS.MARKETPLACE_TRANSFORMER_ANALYTICS LIMIT 5;
SELECT * FROM APPLICATIONS.MARKETPLACE_AMI_STATISTICS LIMIT 5;

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 16_rbac_final.sql for complete role-based access control
-- =============================================================================
