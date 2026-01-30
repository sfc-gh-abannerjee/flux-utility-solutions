-- =============================================================================
-- 25_streamlit_apps.sql
-- Flux Utility Solutions - Streamlit Applications Deployment
-- =============================================================================
-- Purpose: Deploy all Streamlit in Snowflake applications
-- Dependencies: Database and schemas (01), Tables (03-07)
-- 
-- Variable Templating (Snow CLI Jinja2):
--   <% database %>  - Target database name
--   <% warehouse %> - Query warehouse for apps
--
-- Usage:
--   snow sql -f scripts/25_streamlit_apps.sql -D "database=YOUR_DATABASE" -D "warehouse=COMPUTE_WH"
--
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE SCHEMA APPLICATIONS;
USE WAREHOUSE IDENTIFIER('<% warehouse %>');

-- =============================================================================
-- 1. H3 GEOSPATIAL ANALYTICS APP
-- =============================================================================
-- Interactive hexagonal grid visualization for utility infrastructure
-- Features: Meter density, transformer health, load utilization, coverage gaps

CREATE OR REPLACE STREAMLIT FLUX_GEOSPATIAL_H3_APP
    ROOT_LOCATION = '@<% database %>.APPLICATIONS.STREAMLIT_STAGE/geospatial'
    MAIN_FILE = 'streamlit_h3_app.py'
    QUERY_WAREHOUSE = '<% warehouse %>'
    TITLE = 'Flux Geospatial Analytics'
    COMMENT = 'H3 hexagonal grid visualization for utility infrastructure analysis';

-- =============================================================================
-- 2. GRID MAP APP
-- =============================================================================
-- Real-time grid topology visualization with transformer status

CREATE OR REPLACE STREAMLIT FLUX_GRID_MAP_APP
    ROOT_LOCATION = '@<% database %>.APPLICATIONS.STREAMLIT_STAGE'
    MAIN_FILE = 'grid_map.py'
    QUERY_WAREHOUSE = '<% warehouse %>'
    TITLE = 'Flux Grid Map'
    COMMENT = 'Real-time grid topology and transformer status visualization';

-- =============================================================================
-- 3. LOAD ANALYTICS APP
-- =============================================================================
-- Transformer load analysis and capacity planning dashboard

CREATE OR REPLACE STREAMLIT FLUX_LOAD_ANALYTICS_APP
    ROOT_LOCATION = '@<% database %>.APPLICATIONS.STREAMLIT_STAGE'
    MAIN_FILE = 'load_analytics.py'
    QUERY_WAREHOUSE = '<% warehouse %>'
    TITLE = 'Flux Load Analytics'
    COMMENT = 'Transformer load analysis and capacity planning dashboard';

-- =============================================================================
-- 4. OUTAGE DASHBOARD APP
-- =============================================================================
-- Outage tracking and restoration monitoring

CREATE OR REPLACE STREAMLIT FLUX_OUTAGE_DASHBOARD_APP
    ROOT_LOCATION = '@<% database %>.APPLICATIONS.STREAMLIT_STAGE'
    MAIN_FILE = 'outage_dashboard.py'
    QUERY_WAREHOUSE = '<% warehouse %>'
    TITLE = 'Flux Outage Dashboard'
    COMMENT = 'Outage tracking and restoration monitoring dashboard';

-- =============================================================================
-- GRANT ACCESS
-- =============================================================================

GRANT USAGE ON STREAMLIT FLUX_GEOSPATIAL_H3_APP TO ROLE PUBLIC;
GRANT USAGE ON STREAMLIT FLUX_GRID_MAP_APP TO ROLE PUBLIC;
GRANT USAGE ON STREAMLIT FLUX_LOAD_ANALYTICS_APP TO ROLE PUBLIC;
GRANT USAGE ON STREAMLIT FLUX_OUTAGE_DASHBOARD_APP TO ROLE PUBLIC;

-- =============================================================================
-- VERIFY DEPLOYMENT
-- =============================================================================

SELECT 
    'STREAMLIT' AS object_type,
    name AS app_name,
    title,
    root_location,
    main_file,
    query_warehouse,
    created_on
FROM INFORMATION_SCHEMA.STREAMLITS
WHERE SCHEMA_NAME = 'APPLICATIONS'
ORDER BY name;
