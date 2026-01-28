-- =============================================================================
-- 09_cortex_search_services.sql
-- Flux Utility Solutions - Cortex Search Services for RAG
-- =============================================================================
-- Purpose: Create Cortex Search services for customer lookup and document search
-- Dependencies: 05_customers_master.sql
-- Jinja2 Variables:
--   {{ database }}   - Target database name
--   {{ warehouse }}  - Warehouse for search index refresh
-- =============================================================================

USE DATABASE IDENTIFIER('{{ database }}');
USE SCHEMA APPLICATIONS;

-- -----------------------------------------------------------------------------
-- 1. CUSTOMER SEARCH SERVICE
-- -----------------------------------------------------------------------------
-- 686,000 customers indexed for natural language search
-- Supports: name, address, city, county, segment lookup

CREATE OR ALTER CORTEX SEARCH SERVICE CUSTOMER_SEARCH_SERVICE
    ON SEARCH_TEXT
    ATTRIBUTES CUSTOMER_SEGMENT, CITY, SERVICE_COUNTY, ACCOUNT_STATUS
    WAREHOUSE = IDENTIFIER('{{ warehouse }}')
    TARGET_LAG = '1 day'
    COMMENT = 'Customer search - 686K profiles, searchable by name, address, segment'
AS (
    SELECT
        CUSTOMER_ID,
        FULL_NAME,
        CUSTOMER_SEGMENT,
        SERVICE_ADDRESS,
        CITY,
        SERVICE_COUNTY,
        ACCOUNT_STATUS,
        PRIMARY_METER_ID,
        PHONE,
        EMAIL,
        -- Concatenated search text for full-text search
        CONCAT(
            COALESCE(FULL_NAME, ''), ' ',
            COALESCE(CUSTOMER_SEGMENT, ''), ' ',
            COALESCE(SERVICE_ADDRESS, ''), ' ',
            COALESCE(CITY, ''), ' ',
            COALESCE(SERVICE_COUNTY, ''), ' County ',
            COALESCE(ACCOUNT_STATUS, ''), ' customer'
        ) AS SEARCH_TEXT
    FROM {{ database }}.PRODUCTION.CUSTOMERS_MASTER_DATA
);

-- -----------------------------------------------------------------------------
-- 2. AMI METADATA SEARCH SERVICE
-- -----------------------------------------------------------------------------
-- 597,000 meters indexed for meter lookup
-- Supports: meter ID, location, transformer, customer segment

CREATE OR ALTER CORTEX SEARCH SERVICE AMI_METADATA_SEARCH
    ON SEARCH_TEXT
    ATTRIBUTES CUSTOMER_SEGMENT_ID, CITY, ZIP_CODE, COUNTY_NAME, TRANSFORMER_ID, SUBSTATION_ID
    WAREHOUSE = IDENTIFIER('{{ warehouse }}')
    TARGET_LAG = '1 hour'
    COMMENT = 'Meter metadata search - 597K meters, searchable by ID, location, topology'
AS (
    SELECT 
        SEARCH_TEXT,
        METER_ID,
        CUSTOMER_SEGMENT_ID,
        CITY,
        ZIP_CODE,
        COUNTY_NAME,
        TRANSFORMER_ID,
        SUBSTATION_ID,
        AVG_DAILY_KWH
    FROM {{ database }}.PRODUCTION.AMI_METADATA_SEARCHABLE
);

-- Create the searchable view if not exists
CREATE OR ALTER VIEW PRODUCTION.AMI_METADATA_SEARCHABLE AS
SELECT
    m.METER_ID,
    m.CUSTOMER_SEGMENT_ID,
    m.CITY,
    m.ZIP_CODE,
    m.COUNTY_NAME,
    m.TRANSFORMER_ID,
    m.SUBSTATION_ID,
    -- Average daily kWh (computed or from aggregation)
    COALESCE(
        (SELECT AVG(TOTAL_KWH / 30) FROM PRODUCTION.AMI_MONTHLY_USAGE u 
         WHERE u.METER_ID = m.METER_ID),
        0
    ) as AVG_DAILY_KWH,
    -- Search text
    CONCAT(
        m.METER_ID, ' ',
        COALESCE(m.CITY, ''), ' ',
        COALESCE(m.ZIP_CODE, ''), ' ',
        COALESCE(m.COUNTY_NAME, ''), ' ',
        COALESCE(m.TRANSFORMER_ID, ''), ' ',
        COALESCE(m.CUSTOMER_SEGMENT_ID, '')
    ) AS SEARCH_TEXT
FROM PRODUCTION.METER_INFRASTRUCTURE m;

-- -----------------------------------------------------------------------------
-- 3. TECHNICAL MANUALS SEARCH SERVICE
-- -----------------------------------------------------------------------------
-- 20,000 PDF chunks for document RAG
-- Supports: technical manual lookup, troubleshooting guides

-- First create the chunks table if not exists
CREATE TABLE IF NOT EXISTS PRODUCTION.TECHNICAL_MANUALS_PDF_CHUNKS (
    CHUNK_ID VARCHAR(50) PRIMARY KEY,
    DOCUMENT_ID VARCHAR(50),
    DOCUMENT_TYPE VARCHAR(50),
    SOURCE_SYSTEM VARCHAR(50),
    LANGUAGE VARCHAR(10) DEFAULT 'en',
    CHUNK_TEXT TEXT,
    CHUNK_INDEX NUMBER(10,0),
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Technical manual PDF chunks for RAG search';

CREATE OR ALTER CORTEX SEARCH SERVICE TECHNICAL_MANUALS_SEARCH_SERVICE
    ON CHUNK_TEXT
    ATTRIBUTES CHUNK_ID, DOCUMENT_ID, DOCUMENT_TYPE, SOURCE_SYSTEM, LANGUAGE
    WAREHOUSE = IDENTIFIER('{{ warehouse }}')
    TARGET_LAG = '1 minute'
    COMMENT = 'Technical manuals RAG search - 20K document chunks'
AS (
    SELECT 
        CHUNK_ID,
        DOCUMENT_ID, 
        DOCUMENT_TYPE,
        SOURCE_SYSTEM,
        LANGUAGE,
        CHUNK_TEXT
    FROM {{ database }}.PRODUCTION.TECHNICAL_MANUALS_PDF_CHUNKS
);

-- -----------------------------------------------------------------------------
-- 4. GRANT ACCESS
-- -----------------------------------------------------------------------------

GRANT USAGE ON CORTEX SEARCH SERVICE CUSTOMER_SEARCH_SERVICE 
    TO ROLE IDENTIFIER('{{ user_role }}');

GRANT USAGE ON CORTEX SEARCH SERVICE AMI_METADATA_SEARCH 
    TO ROLE IDENTIFIER('{{ user_role }}');

GRANT USAGE ON CORTEX SEARCH SERVICE TECHNICAL_MANUALS_SEARCH_SERVICE 
    TO ROLE IDENTIFIER('{{ user_role }}');

-- -----------------------------------------------------------------------------
-- 5. VERIFICATION
-- -----------------------------------------------------------------------------

-- Show all search services
SHOW CORTEX SEARCH SERVICES IN SCHEMA APPLICATIONS;

-- Test customer search
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    '{{ database }}.APPLICATIONS.CUSTOMER_SEARCH_SERVICE',
    '{
        "query": "residential customer in Houston",
        "columns": ["CUSTOMER_ID", "FULL_NAME", "CITY", "CUSTOMER_SEGMENT"],
        "limit": 5
    }'
);

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 10_cortex_agent.sql to create the Grid Intelligence Agent
-- =============================================================================
