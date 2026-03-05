-- =============================================================================
-- 09_cortex_search_services.sql
-- Flux Utility Solutions - Cortex Search Services for RAG
-- =============================================================================
-- Purpose: Create Cortex Search services for customer lookup and document search
-- Dependencies: 05_customers_master.sql, COMPLIANCE_DOCS table (from sample data)
-- Jinja2 Variables:
--   <% database %>   - Target database name
--   <% warehouse %>  - Warehouse for search index refresh
--   <% user_role %>  - Role to grant access (default: PUBLIC)
--
-- WHAT THIS CREATES:
--   1. CUSTOMER_SEARCH_SERVICE - Customer profile lookup (686K profiles)
--   2. AMI_METADATA_SEARCH - Meter metadata lookup (597K meters)
--   3. TECHNICAL_DOCS_SEARCH - Technical manuals RAG (20K chunks)
--   4. COMPLIANCE_DOCS_SEARCH - NERC/regulatory compliance docs
--
-- NOTE: Service names must match those referenced in 10_cortex_agent.sql
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE WAREHOUSE IDENTIFIER('<% warehouse %>');
USE SCHEMA APPLICATIONS;

-- -----------------------------------------------------------------------------
-- 1. CUSTOMER SEARCH SERVICE
-- -----------------------------------------------------------------------------
-- 686,000 customers indexed for natural language search
-- Supports: name, address, city, county, segment lookup

CREATE OR REPLACE CORTEX SEARCH SERVICE CUSTOMER_SEARCH_SERVICE
    ON SEARCH_TEXT
    ATTRIBUTES CUSTOMER_SEGMENT, CITY, SERVICE_COUNTY, ACCOUNT_STATUS
    WAREHOUSE = <% warehouse %>
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
    FROM <% database %>.PRODUCTION.CUSTOMERS_MASTER_DATA
);

-- -----------------------------------------------------------------------------
-- 2. AMI METADATA SEARCH SERVICE
-- -----------------------------------------------------------------------------
-- 597,000 meters indexed for meter lookup
-- Supports: meter ID, location, transformer, customer segment

-- First create the searchable view
CREATE OR REPLACE VIEW PRODUCTION.AMI_METADATA_SEARCHABLE AS
SELECT
    m.METER_ID,
    m.CUSTOMER_SEGMENT_ID,
    m.CITY,
    m.ZIP_CODE,
    m.COUNTY_NAME,
    m.TRANSFORMER_ID,
    m.SUBSTATION_ID,
    -- Static value for now (can be updated via scheduled task)
    0 as AVG_DAILY_KWH,
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

-- Now create the search service
CREATE OR REPLACE CORTEX SEARCH SERVICE AMI_METADATA_SEARCH
    ON SEARCH_TEXT
    ATTRIBUTES CUSTOMER_SEGMENT_ID, CITY, ZIP_CODE, COUNTY_NAME, TRANSFORMER_ID, SUBSTATION_ID
    WAREHOUSE = <% warehouse %>
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
    FROM <% database %>.PRODUCTION.AMI_METADATA_SEARCHABLE
);

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

CREATE OR REPLACE CORTEX SEARCH SERVICE TECHNICAL_DOCS_SEARCH
    ON CHUNK_TEXT
    ATTRIBUTES CHUNK_ID, DOCUMENT_ID, DOCUMENT_TYPE, SOURCE_SYSTEM, LANGUAGE
    WAREHOUSE = <% warehouse %>
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
    FROM <% database %>.PRODUCTION.TECHNICAL_MANUALS_PDF_CHUNKS
);

-- -----------------------------------------------------------------------------
-- 4. GRANT ACCESS
-- -----------------------------------------------------------------------------

GRANT USAGE ON CORTEX SEARCH SERVICE CUSTOMER_SEARCH_SERVICE 
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');

GRANT USAGE ON CORTEX SEARCH SERVICE AMI_METADATA_SEARCH 
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');

GRANT USAGE ON CORTEX SEARCH SERVICE TECHNICAL_DOCS_SEARCH 
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');

-- -----------------------------------------------------------------------------
-- 5. COMPLIANCE DOCUMENTATION SEARCH SERVICE
-- -----------------------------------------------------------------------------
-- NERC and regulatory compliance documents including TPL-001, FAC-003,
-- EOP-011, CIP standards, and internal utility policies.

USE SCHEMA ML_DEMO;

CREATE OR REPLACE CORTEX SEARCH SERVICE COMPLIANCE_DOCS_SEARCH
    ON CONTENT
    ATTRIBUTES DOC_ID, DOC_TYPE, TITLE, CATEGORY, KEYWORDS, APPLICABILITY
    WAREHOUSE = <% warehouse %>
    TARGET_LAG = '1 hour'
    COMMENT = 'Regulatory compliance document search for Grid Intelligence Agent'
AS (
    SELECT 
        DOC_ID,
        DOC_TYPE,
        TITLE,
        CONTENT,
        CATEGORY,
        KEYWORDS,
        APPLICABILITY,
        EFFECTIVE_DATE::VARCHAR AS EFFECTIVE_DATE,
        REVISION
    FROM <% database %>.ML_DEMO.COMPLIANCE_DOCS
    WHERE CONTENT IS NOT NULL
);

GRANT USAGE ON CORTEX SEARCH SERVICE COMPLIANCE_DOCS_SEARCH 
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');

-- -----------------------------------------------------------------------------
-- 6. VERIFICATION
-- -----------------------------------------------------------------------------

-- Show search services across both schemas
SHOW CORTEX SEARCH SERVICES IN SCHEMA APPLICATIONS;
SHOW CORTEX SEARCH SERVICES IN SCHEMA ML_DEMO;

-- Test customer search
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    '<% database %>.APPLICATIONS.CUSTOMER_SEARCH_SERVICE',
    '{
        "query": "residential customer in Houston",
        "columns": ["CUSTOMER_ID", "FULL_NAME", "CITY", "CUSTOMER_SEGMENT"],
        "limit": 5
    }'
);

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Search services created:
--   APPLICATIONS.CUSTOMER_SEARCH_SERVICE
--   APPLICATIONS.AMI_METADATA_SEARCH
--   PRODUCTION.TECHNICAL_DOCS_SEARCH
--   ML_DEMO.COMPLIANCE_DOCS_SEARCH
-- Next: Run 10_cortex_agent.sql to create the Grid Intelligence Agent
-- =============================================================================
