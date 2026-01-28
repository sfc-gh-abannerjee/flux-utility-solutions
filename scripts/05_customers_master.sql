-- =============================================================================
-- 05_customers_master.sql
-- Flux Utility Solutions - Customer Data Tables
-- =============================================================================
-- Purpose: Create customer master data and related tables
-- Dependencies: 04_meters_infrastructure.sql
-- Jinja2 Variables:
--   {{ database }}  - Target database name
-- =============================================================================

USE DATABASE IDENTIFIER('{{ database }}');
USE SCHEMA PRODUCTION;

-- -----------------------------------------------------------------------------
-- 1. CUSTOMERS_MASTER_DATA
-- -----------------------------------------------------------------------------
-- 686,000 customer records with demographic and account information
-- Naming convention: CUST-XXXXXXXX

CREATE OR ALTER TABLE CUSTOMERS_MASTER_DATA (
    -- Primary key
    CUSTOMER_ID VARCHAR(20) NOT NULL PRIMARY KEY,
    
    -- Account information
    ACCOUNT_NUMBER VARCHAR(20),
    PRIMARY_METER_ID VARCHAR(20),
    
    -- Personal information
    FIRST_NAME VARCHAR(50),
    LAST_NAME VARCHAR(50),
    FULL_NAME VARCHAR(100),
    PHONE VARCHAR(20),
    EMAIL VARCHAR(100),
    
    -- Service address
    SERVICE_ADDRESS VARCHAR(200),
    CITY VARCHAR(50),
    STATE VARCHAR(2) DEFAULT 'TX',
    ZIP_CODE VARCHAR(10),
    SERVICE_COUNTY VARCHAR(50),
    
    -- Location
    LATITUDE FLOAT,
    LONGITUDE FLOAT,
    
    -- Account status
    ACCOUNT_STATUS VARCHAR(20),  -- ACTIVE, INACTIVE, SUSPENDED
    ENROLLMENT_DATE DATE,
    DISCONNECTION_DATE DATE,
    
    -- Segmentation
    CUSTOMER_SEGMENT VARCHAR(20),  -- RESIDENTIAL, COMMERCIAL, INDUSTRIAL
    INCOME_SEGMENT VARCHAR(20),    -- LOW, LOWER_MIDDLE, MIDDLE, UPPER_MIDDLE, HIGH
    
    -- Multi-tenant support
    CUSTOMERS_ON_METER NUMBER(5,0) DEFAULT 1,
    IS_MULTI_FAMILY BOOLEAN DEFAULT FALSE,
    
    -- Embeddings for Cortex Search
    CUSTOMER_EMBEDDING VECTOR(FLOAT, 1024),
    
    -- Audit
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (CITY, ZIP_CODE, CUSTOMER_SEGMENT)
COMMENT = 'Customer master data - 686,000 profiles with demographics';

-- -----------------------------------------------------------------------------
-- 2. CUSTOMER_SEGMENT_CONFIG
-- -----------------------------------------------------------------------------
-- Configuration for customer segmentation

CREATE OR ALTER TABLE CUSTOMER_SEGMENT_CONFIG (
    SEGMENT_ID VARCHAR(20) NOT NULL PRIMARY KEY,
    SEGMENT_NAME VARCHAR(50),
    SEGMENT_DESCRIPTION VARCHAR(200),
    AVG_MONTHLY_KWH NUMBER(10,2),
    PEAK_HOUR_MULTIPLIER NUMBER(5,2),
    SOLAR_ADOPTION_RATE NUMBER(5,4),
    EV_ADOPTION_RATE NUMBER(5,4),
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Customer segment configuration for load profiling';

-- Insert standard segments
INSERT INTO CUSTOMER_SEGMENT_CONFIG (SEGMENT_ID, SEGMENT_NAME, SEGMENT_DESCRIPTION, AVG_MONTHLY_KWH, PEAK_HOUR_MULTIPLIER, SOLAR_ADOPTION_RATE, EV_ADOPTION_RATE)
SELECT * FROM VALUES
    ('RES-LOW', 'Residential Low Income', 'Low-income single-family residential', 800, 1.2, 0.02, 0.01),
    ('RES-MID', 'Residential Middle', 'Middle-income single-family residential', 1200, 1.3, 0.08, 0.05),
    ('RES-HIGH', 'Residential High Income', 'High-income single-family residential', 2000, 1.4, 0.15, 0.12),
    ('RES-MULTI', 'Multi-Family Residential', 'Apartments and condos', 600, 1.1, 0.01, 0.02),
    ('COM-SMALL', 'Small Commercial', 'Small retail and office', 3000, 1.5, 0.05, 0.03),
    ('COM-LARGE', 'Large Commercial', 'Large retail, office, and warehouse', 15000, 1.6, 0.03, 0.02),
    ('IND-LIGHT', 'Light Industrial', 'Light manufacturing and distribution', 50000, 1.3, 0.02, 0.01),
    ('IND-HEAVY', 'Heavy Industrial', 'Heavy manufacturing', 200000, 1.2, 0.01, 0.005)
WHERE NOT EXISTS (SELECT 1 FROM CUSTOMER_SEGMENT_CONFIG);

-- -----------------------------------------------------------------------------
-- 3. CUSTOMER_INCOME_SEGMENT_MAPPING
-- -----------------------------------------------------------------------------
-- Mapping table for income-based load multipliers

CREATE OR ALTER TABLE CUSTOMER_INCOME_SEGMENT_MAPPING (
    MAPPING_ID NUMBER(10,0) AUTOINCREMENT PRIMARY KEY,
    CUSTOMER_SEGMENT_ID VARCHAR(20),
    INCOME_SEGMENT VARCHAR(20),
    LOAD_MULTIPLIER NUMBER(5,2),
    SOLAR_FLAG BOOLEAN,
    EV_FLAG BOOLEAN,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Income segment to load multiplier mapping';

-- -----------------------------------------------------------------------------
-- 4. ENERGY_BURDEN_ANALYSIS (View)
-- -----------------------------------------------------------------------------
-- Energy burden analysis view for affordability insights

CREATE OR ALTER VIEW APPLICATIONS.ENERGY_BURDEN_ANALYSIS AS
SELECT 
    c.CUSTOMER_ID,
    c.FULL_NAME,
    c.SERVICE_ADDRESS,
    c.CITY,
    c.ZIP_CODE,
    c.INCOME_SEGMENT,
    c.CUSTOMER_SEGMENT,
    c.CUSTOMERS_ON_METER,
    m.METER_ID,
    -- This will be populated after AMI tables are created
    NULL::NUMBER(10,2) as AVG_MONTHLY_KWH,
    NULL::NUMBER(10,2) as AVG_MONTHLY_COST,
    NULL::NUMBER(5,2) as ENERGY_BURDEN_PCT,
    CASE 
        WHEN c.INCOME_SEGMENT = 'LOW' THEN 'High Burden Risk'
        WHEN c.INCOME_SEGMENT = 'LOWER_MIDDLE' THEN 'Moderate Burden Risk'
        ELSE 'Low Burden Risk'
    END as BURDEN_CATEGORY
FROM CUSTOMERS_MASTER_DATA c
LEFT JOIN METER_INFRASTRUCTURE m ON c.PRIMARY_METER_ID = m.METER_ID;

-- -----------------------------------------------------------------------------
-- 5. VERIFICATION
-- -----------------------------------------------------------------------------

SELECT 'CUSTOMERS_MASTER_DATA' as table_name, COUNT(*) as row_count FROM CUSTOMERS_MASTER_DATA
UNION ALL
SELECT 'CUSTOMER_SEGMENT_CONFIG', COUNT(*) FROM CUSTOMER_SEGMENT_CONFIG
UNION ALL
SELECT 'CUSTOMER_INCOME_SEGMENT_MAPPING', COUNT(*) FROM CUSTOMER_INCOME_SEGMENT_MAPPING;

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 06_ami_readings_pipeline.sql to create AMI time-series tables
-- =============================================================================
