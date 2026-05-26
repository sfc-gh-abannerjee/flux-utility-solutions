-- =============================================================================
-- 08_outage_history_search.sql
-- Flux Utility Solutions — Create OUTAGE_HISTORY_SEARCH Cortex Search Service
-- =============================================================================
-- Purpose: Fuzzy-searchable index over 18,689 outage events.
--          Backs the search_outages tool on GRID_INTELLIGENCE_AGENT.
--
-- Prerequisites: 07_outage_semantic_view.sql deployed
--               (OUTAGE_HISTORY_SEARCHABLE view must exist)
--
-- Variable Templating (Snow CLI Jinja2):
--   <% database %>   - Target database (e.g., FLUX_DB)
--   <% warehouse %>  - Target warehouse (e.g., FLUX_WH)
--   <% user_role %>  - Role to grant USAGE (default: PUBLIC)
--
-- Usage:
--   snow sql -f scripts/realistic_data/08_outage_history_search.sql \
--       -D "database=FLUX_DB" -D "warehouse=FLUX_WH"
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE WAREHOUSE IDENTIFIER('<% warehouse %>');
USE SCHEMA APPLICATIONS;

-- -----------------------------------------------------------------------------
-- 1. CREATE CORTEX SEARCH SERVICE
--    Source: OUTAGE_HISTORY_SEARCHABLE (created in 07_outage_semantic_view.sql)
--    Search column: SEARCH_TEXT (pre-concatenated full-text blob)
--    Attributes: key fields returned with each search hit
-- -----------------------------------------------------------------------------

CREATE OR REPLACE CORTEX SEARCH SERVICE OUTAGE_HISTORY_SEARCH
    ON SEARCH_TEXT
    ATTRIBUTES
        OUTAGE_ID,
        CAUSE,
        STATUS,
        SUBSTATION_ID,
        TRANSFORMER_ID,
        OUTAGE_START_TIME,
        OUTAGE_END_TIME,
        AFFECTED_CUSTOMERS,
        OUTAGE_DURATION_MINUTES,
        SEVERITY
    WAREHOUSE = IDENTIFIER('<% warehouse %>')
    TARGET_LAG = '1 hour'
    COMMENT = 'Fuzzy search over 18K+ outage events (July 2024). Hurricane Beryl: 13,637 WEATHER outages on 2024-07-08.'
AS (
    SELECT
        OUTAGE_ID,
        CAUSE,
        STATUS,
        SUBSTATION_ID,
        TRANSFORMER_ID,
        OUTAGE_START_TIME,
        OUTAGE_END_TIME,
        AFFECTED_CUSTOMERS,
        OUTAGE_DURATION_MINUTES,
        SEVERITY,
        SEARCH_TEXT
    FROM <% database %>.PRODUCTION.OUTAGE_HISTORY_SEARCHABLE
);

-- -----------------------------------------------------------------------------
-- 2. GRANT ACCESS
-- -----------------------------------------------------------------------------

GRANT USAGE ON CORTEX SEARCH SERVICE OUTAGE_HISTORY_SEARCH
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');

-- -----------------------------------------------------------------------------
-- 3. VERIFY — poll until indexing is done
-- -----------------------------------------------------------------------------

SHOW CORTEX SEARCH SERVICES IN SCHEMA APPLICATIONS;

-- Smoke test: Beryl impact query (expect 13,637 WEATHER outages)
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    '<% database %>.APPLICATIONS.OUTAGE_HISTORY_SEARCH',
    $q${"query": "Beryl impact", "columns": ["OUTAGE_ID","CAUSE","STATUS","AFFECTED_CUSTOMERS","OUTAGE_START_TIME"], "limit": 5}$q$
);

-- Smoke test: transformer overload query
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    '<% database %>.APPLICATIONS.OUTAGE_HISTORY_SEARCH',
    $q${"query": "transformer overload restoration", "columns": ["OUTAGE_ID","CAUSE","TRANSFORMER_ID","AFFECTED_CUSTOMERS"], "limit": 5}$q$
);

-- Row count sanity check
SELECT COUNT(*) AS indexed_rows
FROM <% database %>.PRODUCTION.OUTAGE_HISTORY_SEARCHABLE;
-- Expected: 18,689

-- =============================================================================
-- END
-- Next: Run 09_agent_alter_outage_tool.sql to add search_outages to GIA
-- =============================================================================
