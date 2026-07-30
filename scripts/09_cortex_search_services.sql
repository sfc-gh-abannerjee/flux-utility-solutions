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
    COMMENT = 'Customer search - 100K profiles, searchable by name, address, segment'
AS (
    SELECT
        CUSTOMER_ID,
        -- Compute FULL_NAME from FIRST_NAME + LAST_NAME (actual table columns)
        CONCAT(COALESCE(FIRST_NAME, ''), ' ', COALESCE(LAST_NAME, '')) AS FULL_NAME,
        -- Map CUSTOMER_CLASS -> CUSTOMER_SEGMENT for agent compatibility
        CUSTOMER_CLASS AS CUSTOMER_SEGMENT,
        SERVICE_ADDRESS,
        CITY,
        -- Map STATE -> SERVICE_COUNTY (county not in table, use state as fallback)
        STATE AS SERVICE_COUNTY,
        ACCOUNT_STATUS,
        -- Map METER_ID -> PRIMARY_METER_ID for agent compatibility
        METER_ID AS PRIMARY_METER_ID,
        -- Concatenated search text for full-text search
        CONCAT(
            COALESCE(FIRST_NAME, ''), ' ',
            COALESCE(LAST_NAME, ''), ' ',
            COALESCE(CUSTOMER_CLASS, ''), ' ',
            COALESCE(SERVICE_ADDRESS, ''), ' ',
            COALESCE(CITY, ''), ' ',
            COALESCE(STATE, ''), ' ',
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
-- Maps actual METER_INFRASTRUCTURE columns to expected search service schema
--
-- 2026-07-29: SUBSTATION_ID was hardcoded to NULL here ("not in actual table"),
-- which meant the substation attribute filter matched nothing for all 100,000
-- rows and the agent's search_meters tool was effectively broken since it was
-- built. After the topology regeneration (scripts/31) meters carry a real
-- TRANSFORMER_ID and CIRCUIT_ID, so the substation is now resolvable by join.
-- Also surfaces the human-readable feeder/substation NAMES so operators can
-- filter and search by name instead of by key.
CREATE OR REPLACE VIEW PRODUCTION.AMI_METADATA_SEARCHABLE AS
SELECT
    m.METER_ID,
    -- Map CUSTOMER_CLASS -> CUSTOMER_SEGMENT_ID for agent compatibility
    m.CUSTOMER_CLASS AS CUSTOMER_SEGMENT_ID,
    m.CITY,
    -- ZIP_CODE genuinely absent from METER_INFRASTRUCTURE; still a placeholder
    NULL::VARCHAR AS ZIP_CODE,
    m.COUNTY_NAME,
    m.TRANSFORMER_ID,
    t.SUBSTATION_ID                                   AS SUBSTATION_ID,
    m.CIRCUIT_ID                                      AS CIRCUIT_ID,
    s.SUBSTATION_NAME                                 AS SUBSTATION_NAME,
    c.CIRCUIT_NAME                                    AS CIRCUIT_NAME,
    -- Static value for now (can be updated via scheduled task)
    0 as AVG_DAILY_KWH,
    -- Search text
    CONCAT(
        m.METER_ID, ' ',
        COALESCE(m.CITY, ''), ' ',
        COALESCE(m.COUNTY_NAME, ''), ' ',
        COALESCE(m.TRANSFORMER_ID, ''), ' ',
        COALESCE(m.CIRCUIT_ID, ''), ' ',
        COALESCE(c.CIRCUIT_NAME, ''), ' ',
        COALESCE(t.SUBSTATION_ID, ''), ' ',
        COALESCE(s.SUBSTATION_NAME, ''), ' ',
        COALESCE(m.CUSTOMER_CLASS, '')
    ) AS SEARCH_TEXT
FROM PRODUCTION.METER_INFRASTRUCTURE m
LEFT JOIN PRODUCTION.TRANSFORMER_METADATA t ON m.TRANSFORMER_ID = t.TRANSFORMER_ID
LEFT JOIN PRODUCTION.CIRCUIT_METADATA    c ON m.CIRCUIT_ID     = c.CIRCUIT_ID
LEFT JOIN PRODUCTION.SUBSTATIONS         s ON t.SUBSTATION_ID  = s.SUBSTATION_ID;

-- Now create the search service
CREATE OR REPLACE CORTEX SEARCH SERVICE AMI_METADATA_SEARCH
    ON SEARCH_TEXT
    ATTRIBUTES CUSTOMER_SEGMENT_ID, CITY, ZIP_CODE, COUNTY_NAME, TRANSFORMER_ID, SUBSTATION_ID, CIRCUIT_ID, SUBSTATION_NAME, CIRCUIT_NAME
    WAREHOUSE = <% warehouse %>
    TARGET_LAG = '1 hour'
    COMMENT = 'Meter metadata search - 100K meters, searchable by meter id, location, and topology (transformer / feeder / substation, by key or by name)'
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
        CIRCUIT_ID,
        SUBSTATION_NAME,
        CIRCUIT_NAME,
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
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    -- 2026-07-29: live PRODUCTION.TECHNICAL_MANUALS_PDF_CHUNKS carries DOCUMENT_TITLE,
    -- and UTILITY_PDF_DOCS_SEARCH indexes it as an attribute. This script omitted the
    -- column, so a fresh deploy failed with "invalid identifier 'DOCUMENT_TITLE'".
    -- Appended at the end of the list because CREATE OR ALTER TABLE cannot add a
    -- column before the end of an existing column list.
    DOCUMENT_TITLE VARCHAR(500)
)
COMMENT = 'Technical manual PDF chunks for RAG search';

-- 2026-07-29: fully qualified to PRODUCTION. This file runs under
-- "USE SCHEMA APPLICATIONS" (line 23), so an unqualified name created
-- APPLICATIONS.TECHNICAL_DOCS_SEARCH -- but 10_cortex_agent.sql wires the agent to
-- PRODUCTION.TECHNICAL_DOCS_SEARCH, which is also where it lives in the live account.
-- A fresh deploy therefore failed in script 10 with "Cortex Search Service
-- 'PRODUCTION.TECHNICAL_DOCS_SEARCH' does not exist".
CREATE OR REPLACE CORTEX SEARCH SERVICE PRODUCTION.TECHNICAL_DOCS_SEARCH
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

GRANT USAGE ON CORTEX SEARCH SERVICE PRODUCTION.TECHNICAL_DOCS_SEARCH 
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');

-- -----------------------------------------------------------------------------
-- 5. COMPLIANCE DOCUMENTATION SEARCH SERVICE
-- -----------------------------------------------------------------------------
-- NERC and regulatory compliance documents including TPL-001, FAC-003,
-- EOP-011, CIP standards, and internal utility policies.

USE SCHEMA ML_DEMO;


-- -----------------------------------------------------------------------------
-- OUTAGE_HISTORY_SEARCH  +  UTILITY_PDF_DOCS_SEARCH
-- -----------------------------------------------------------------------------
-- 2026-07-29: the live account runs SIX Cortex Search services but this script only
-- created FOUR. The two below were missing entirely, and 10_cortex_agent.sql wires the
-- agent to both -- so a fresh deploy failed with
--   Cortex Search Service 'APPLICATIONS.OUTAGE_HISTORY_SEARCH' does not exist
-- PRODUCTION.OUTAGE_HISTORY_SEARCHABLE, which OUTAGE_HISTORY_SEARCH indexes, was also
-- created by no script. Definitions below are the live ones, captured verbatim.

CREATE OR REPLACE VIEW PRODUCTION.OUTAGE_HISTORY_SEARCHABLE AS
SELECT
    OUTAGE_ID, CIRCUIT_ID, SUBSTATION_ID, TRANSFORMER_ID,
    OUTAGE_START_TIME, OUTAGE_END_TIME, STATUS, CAUSE,
    AFFECTED_CUSTOMERS, AFFECTED_TRANSFORMERS, CREW_ASSIGNED,
    ESTIMATED_RESTORATION, ACTUAL_RESTORATION, OUTAGE_DURATION_MINUTES,
    NOTES, CREATED_AT, UPDATED_AT,
    DATE(OUTAGE_START_TIME) AS OUTAGE_DATE,
    HOUR(OUTAGE_START_TIME) AS OUTAGE_HOUR,
    CASE
        WHEN AFFECTED_CUSTOMERS >= 100 THEN 'CRITICAL'
        WHEN AFFECTED_CUSTOMERS >= 10  THEN 'HIGH'
        WHEN AFFECTED_CUSTOMERS >= 2   THEN 'MEDIUM'
        ELSE                                'LOW'
    END AS SEVERITY,
    OUTAGE_ID
        || ' ' || COALESCE(CAUSE,  'unknown_cause')
        || ' ' || COALESCE(STATUS, 'unknown_status')
        || ' on substation ' || COALESCE(SUBSTATION_ID,  'unknown_sub')
        || ' transformer '   || COALESCE(TRANSFORMER_ID, 'unknown_xfmr')
        || ' '               || COALESCE(NOTES, '')  AS SEARCH_TEXT
FROM PRODUCTION.OUTAGE_RESTORATION_TRACKER;

CREATE OR REPLACE CORTEX SEARCH SERVICE APPLICATIONS.OUTAGE_HISTORY_SEARCH
    ON SEARCH_TEXT
    ATTRIBUTES OUTAGE_ID, CAUSE, STATUS, SUBSTATION_ID, TRANSFORMER_ID,
               OUTAGE_START_TIME, OUTAGE_END_TIME, AFFECTED_CUSTOMERS,
               OUTAGE_DURATION_MINUTES, SEVERITY
    WAREHOUSE = <% warehouse %>
    TARGET_LAG = '1 hour'
    COMMENT = 'Fuzzy search over 18K+ outage events (July 2024), incl. Hurricane Beryl 2024-07-08.'
AS (
    SELECT OUTAGE_ID, CAUSE, STATUS, SUBSTATION_ID, TRANSFORMER_ID,
           OUTAGE_START_TIME, OUTAGE_END_TIME, AFFECTED_CUSTOMERS,
           OUTAGE_DURATION_MINUTES, SEVERITY, SEARCH_TEXT
    FROM PRODUCTION.OUTAGE_HISTORY_SEARCHABLE
);

CREATE OR REPLACE CORTEX SEARCH SERVICE APPLICATIONS.UTILITY_PDF_DOCS_SEARCH
    ON CHUNK_TEXT
    -- DOCUMENT_TITLE omitted deliberately: the live service indexes it, but
    -- TECHNICAL_MANUALS_PDF_CHUNKS is created by BOTH 50_load_seed_data.sql and this
    -- script, and 50 runs first -- so a column added here never lands on a fresh
    -- deploy. Rather than duplicate the column across two owners, the attribute is
    -- dropped; add it to script 50's DDL if title filtering is needed.
    ATTRIBUTES CHUNK_ID, DOCUMENT_ID, DOCUMENT_TYPE,
               SOURCE_SYSTEM, LANGUAGE
    WAREHOUSE = <% warehouse %>
    TARGET_LAG = '1 hour'
    COMMENT = 'CSS over S3-stage PDF chunks (SOURCE_SYSTEM=S3_STAGE). Pairs with TECHNICAL_DOCS_SEARCH.'
AS (
    SELECT CHUNK_ID, DOCUMENT_ID, DOCUMENT_TYPE,
           SOURCE_SYSTEM, LANGUAGE, CHUNK_TEXT
    FROM PRODUCTION.TECHNICAL_MANUALS_PDF_CHUNKS
    WHERE SOURCE_SYSTEM = 'S3_STAGE'
      AND CHUNK_TEXT IS NOT NULL
);

-- -----------------------------------------------------------------------------
-- ML_DEMO.COMPLIANCE_DOCS  (prerequisite for COMPLIANCE_DOCS_SEARCH below)
-- -----------------------------------------------------------------------------
-- 2026-07-29: this table was referenced by scripts 09 and 10 but CREATED BY NEITHER.
-- It existed in the live account only because it had been made ad hoc, so a fresh
-- deploy failed with "Object 'ML_DEMO.COMPLIANCE_DOCS' does not exist" and the
-- COMPLIANCE_DOCS_SEARCH service could never be built. The 8 documents below are the
-- real NERC / ERCOT / internal standards captured from the live table, so the search
-- service is now reproducible from source.
--
-- ML_DEMO schema is created by 30_ops_center_dependencies.sql, which runs earlier in
-- SCRIPT_ORDER.
CREATE SCHEMA IF NOT EXISTS ML_DEMO;

CREATE TABLE IF NOT EXISTS ML_DEMO.COMPLIANCE_DOCS (
    DOC_ID          VARCHAR(50) PRIMARY KEY,
    DOC_TYPE        VARCHAR(50),
    TITLE           VARCHAR(500),
    CONTENT         VARCHAR(16777216),
    CATEGORY        VARCHAR(100),
    KEYWORDS        VARCHAR(1000),
    APPLICABILITY   VARCHAR(500),
    EFFECTIVE_DATE  DATE,
    REVISION        VARCHAR(20),
    REGULATORY_BODY VARCHAR(100),
    CREATED_AT      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Compliance/reliability standards indexed by COMPLIANCE_DOCS_SEARCH';

-- Idempotent seed: only load when empty, so a redeploy never duplicates rows.
INSERT INTO ML_DEMO.COMPLIANCE_DOCS
    (DOC_ID, DOC_TYPE, TITLE, CONTENT, CATEGORY, KEYWORDS, APPLICABILITY,
     EFFECTIVE_DATE, REVISION, REGULATORY_BODY)
SELECT * FROM (
  SELECT * FROM VALUES
    ('ERCOT-OP-01', 'Operating Procedure', 'ERCOT Grid Operations for Extreme Weather', 'Purpose: Provide operational guidance for managing the ERCOT grid during extreme weather events that may cause cascading failures.

Winter Storm Procedures (Lessons from Uri 2021):
1. Pre-Event Preparation:
   - Review weatherization status of generation facilities
   - Pre-position operating reserves above normal levels
   - Coordinate with natural gas pipeline operators
   - Prepare load shedding rotation schedules

2. During Event Operations:
   - Monitor generation availability hourly
   - Track natural gas curtailments to generators
   - Implement controlled rotating outages if necessary
   - Maintain system frequency above 59.4 Hz

3. Cascade Prevention Measures:
   - Island formation if interconnection becomes unstable
   - Automatic generator tripping to prevent damage
   - Load shedding to match available generation
   - Priority restoration to critical infrastructure

Summer Heat Wave Procedures:
1. Monitor transformer loading and enable cooling
2. Curtail non-essential load during peak hours
3. Activate demand response programs
4. Request emergency energy from neighboring regions

Critical Infrastructure Priority:
1. Hospitals and medical facilities
2. Water treatment plants
3. Emergency services (police, fire, 911)
4. Natural gas compressor stations
5. Telecommunications hubs', 'Operating Procedures', 'extreme weather, winter storm, heat wave, load shedding, cascade prevention', 'ERCOT Control Room Operators, QSEs, Transmission Operators', DATE '2024-03-01', '2024.1', 'NERC'),
    ('NERC-EOP-011-3', 'Reliability Standard', 'Emergency Operations', 'Purpose: To address capacity and energy emergencies and to minimize impacts to the Interconnection.

Emergency Levels for Cascade Risk:
- Energy Emergency Alert Level 1 (EEA1): All resources in use, operating reserves may be below required minimum
- Energy Emergency Alert Level 2 (EEA2): Load management procedures in effect
- Energy Emergency Alert Level 3 (EEA3): Firm load interruption imminent or in progress

Cascade Prevention During Emergencies:
R1. Each Balancing Authority shall have an Operating Plan to mitigate capacity and energy emergencies.
R2. Operating Plan must include:
- Notification procedures to Reliability Coordinator
- Criteria for declaring emergency alerts
- Load reduction procedures (voluntary and mandatory)
- Capacity reserve sharing arrangements

Automatic Load Shedding:
- Under-frequency load shedding (UFLS) programs activated at specific frequency thresholds
- Under-voltage load shedding (UVLS) for voltage collapse prevention
- Coordinated with neighboring systems to prevent cascading outages

Violation Risk Factor: High
Time Horizon: Emergency Operations', 'Emergency Operations', 'emergency operations, load shedding, UFLS, UVLS, cascade prevention', 'Balancing Authorities, Transmission Operators', DATE '2023-10-01', '3', 'NERC'),
    ('NERC-FAC-001-3', 'Reliability Standard', 'Facility Interconnection Requirements', 'Purpose: To avoid adverse impacts on the reliability of the Bulk Electric System at or beyond the Point of Interconnection.

Requirements for Cascade Prevention:
R1. Each Transmission Owner shall document, maintain, and publish Facility interconnection requirements for generation and transmission Facilities.
R2. Interconnection requirements must address:
- Power factor design criteria
- Voltage regulation requirements
- Fault current capability
- System protection requirements
- Metering requirements

Cascade Protection Requirements:
- Adequate fault clearing capability to prevent cascade propagation
- Proper coordination of protection systems between interconnected systems
- Real-time monitoring of interconnection flows
- Automatic under-frequency load shedding schemes

Violation Risk Factor: Medium
Time Horizon: Operations Planning, Same-day Operations', 'Facility Design', 'interconnection, fault clearing, protection coordination, cascade prevention', 'Transmission Owners, Generator Owners', DATE '2023-07-01', '3', 'NERC'),
    ('NERC-PRC-006-5', 'Reliability Standard', 'Automatic Underfrequency Load Shedding', 'Purpose: To establish design and documentation requirements for automatic underfrequency load shedding (UFLS) programs to arrest declining frequency, assist recovery of frequency following underfrequency events, and provide last resort system preservation measures.

UFLS Requirements for Cascade Prevention:
R1. Each Planning Coordinator shall develop and document a UFLS program.
R2. The UFLS program shall:
- Arrest frequency decline within the Interconnection
- Be coordinated with neighboring Planning Coordinators
- Include automatic time-delayed underfrequency island detection

Load Shedding Frequency Thresholds (typical):
- 59.5 Hz: First stage (5% load shed)
- 59.0 Hz: Second stage (10% load shed)  
- 58.5 Hz: Third stage (15% load shed)
- Below 58.5 Hz: Additional stages as required

Cascade Interruption Strategy:
- Rapid load reduction to arrest frequency decline
- Islanding detection to prevent cascading into healthy areas
- Automatic restoration when frequency recovers

Violation Risk Factor: High
Time Horizon: Long-term Planning', 'Protection Systems', 'UFLS, underfrequency, load shedding, cascade arrest', 'Planning Coordinators, Transmission Planners, Distribution Providers', DATE '2024-01-01', '5', 'NERC'),
    ('NERC-PRC-023-6', 'Reliability Standard', 'Transmission Relay Loadability', 'Purpose: To ensure that transmission relays are set such that they do not limit transmission loadability and do not inadvertently trip during recoverable system conditions.

Relay Coordination for Cascade Prevention:
R1. Transmission Owners shall set relays so they do not trip during recoverable transients.
R2. Relays must remain in service during:
- Stable power swings
- Dynamic transfers
- Temporary overloads within equipment ratings

Protective Relay Requirements:
- Phase distance relays must not restrict circuit loadability
- Ground distance relays must coordinate properly
- Overcurrent relays must allow emergency loading
- Communication-aided schemes must be properly coordinated

Anti-Cascade Relay Features:
- Out-of-step blocking to prevent tripping on power swings
- Load encroachment logic to prevent spurious trips
- Fault type discrimination to prevent sympathetic tripping
- Breaker failure protection with proper coordination

Violation Risk Factor: High
Time Horizon: Real-time Operations, Long-term Planning', 'Protection Systems', 'relay settings, protection coordination, power swings, cascade prevention', 'Transmission Owners, Generator Owners', DATE '2023-07-01', '6', 'NERC'),
    ('NERC-TOP-001-5', 'Reliability Standard', 'Transmission Operations', 'Purpose: To prevent instability, uncontrolled separation, or Cascading outages that adversely impact the reliability of the Interconnection.

Real-Time Cascade Prevention Requirements:
R1. Each Transmission Operator shall perform operational planning analysis.
R2. Each Transmission Operator shall monitor its Transmission Operator Area to ensure that:
- System Operating Limits and Interconnection Reliability Operating Limits are not exceeded
- Real and Reactive Power flows are within operational limits
- Voltage profiles are maintained within acceptable ranges

R3. Operators must take corrective action when anticipating or experiencing:
- Equipment overloads
- Abnormal frequency conditions  
- Voltage deviations outside acceptable range
- Imminent cascading conditions

Emergency Procedures:
- Implement load shedding when necessary to prevent cascade
- Coordinate with neighboring Transmission Operators
- Restore system to normal operation as quickly as safely possible

Violation Risk Factor: High
Time Horizon: Real-time Operations, Same-day Operations', 'System Operations', 'real-time operations, system limits, load shedding, cascade prevention', 'Transmission Operators, Reliability Coordinators', DATE '2024-04-01', '5', 'NERC'),
    ('NERC-TPL-001-5.1', 'Reliability Standard', 'Transmission System Planning Performance Requirements', 'Purpose: Establish Transmission system planning performance requirements within the planning horizon to develop a Bulk Electric System (BES) that will operate reliably over a broad spectrum of System conditions and following a wide range of probable Contingencies.

Requirements:
R1. Each Planning Coordinator and Transmission Planner shall maintain System models for performing the studies needed to complete the Transmission System Planning assessments.
R2. Each Planning Coordinator and Transmission Planner shall perform assessments of the Transmission system performance.
R3. For the steady state portion of the Planning Assessment, each Transmission Planner and Planning Coordinator shall perform studies for the planning events.

Cascade Prevention Requirements:
- System must maintain stability following N-1 contingencies
- System must demonstrate acceptable performance for multiple facility outages (N-1-1)
- Cascading shall not occur for any single Contingency
- Thermal limits, voltage limits, and stability limits must not be exceeded

Violation Risk Factor: High
Time Horizon: Long-term Planning', 'Transmission Planning', 'cascade prevention, N-1 contingency, transmission planning, system stability', 'Transmission Planners, Planning Coordinators, Transmission Operators', DATE '2024-01-01', '5.1', 'NERC'),
    ('UTIL-STD-001', 'Internal Standard', 'Regional Utility Transformer Loading Standards', 'Purpose: Establish loading limits and monitoring requirements for distribution transformers to prevent thermal damage and cascading failures.

Normal Loading Limits:
- Residential transformers: 100% nameplate for continuous operation
- Commercial transformers: 100% nameplate for continuous operation
- Industrial transformers: Per customer agreement

Emergency Loading Limits:
- Up to 120% for 4 hours maximum (with enhanced monitoring)
- Up to 140% for 30 minutes (emergency only)
- Above 140%: Immediate load reduction required

Temperature Monitoring Thresholds:
- Hot spot temperature alarm: 110C
- Hot spot temperature trip: 130C
- Top oil temperature alarm: 95C
- Top oil temperature trip: 105C

Cascade Prevention Requirements:
1. Transformers exceeding 90% load for >2 hours require investigation
2. Adjacent transformer loading must be monitored when one unit fails
3. Automatic load transfer schemes must be tested annually
4. Mobile transformer deployment criteria established

Summer Peak Procedures:
- Pre-position mobile transformers in high-risk areas
- Enable enhanced oil cooling systems
- Monitor thermal stress accumulation
- Coordinate with ERCOT for system-wide conditions

Violation of these standards may result in equipment damage and potential cascading outages affecting customer service.', 'Internal Standards', 'transformer loading, thermal limits, summer peak, cascade prevention', 'Distribution Operations, Engineering, Planning', DATE '2024-01-15', '2024.1', 'NERC')
) AS v(DOC_ID, DOC_TYPE, TITLE, CONTENT, CATEGORY, KEYWORDS, APPLICABILITY,
       EFFECTIVE_DATE, REVISION, REGULATORY_BODY)
WHERE NOT EXISTS (SELECT 1 FROM ML_DEMO.COMPLIANCE_DOCS);

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
