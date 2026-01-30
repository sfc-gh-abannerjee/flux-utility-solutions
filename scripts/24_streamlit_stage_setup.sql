-- =============================================================================
-- 24_streamlit_stage_setup.sql
-- Flux Utility Solutions - Streamlit Stage and File Upload
-- =============================================================================
-- Purpose: Create stage and upload Streamlit app files
-- Run BEFORE: 25_streamlit_apps.sql
-- 
-- Variable Templating (Snow CLI Jinja2):
--   <% database %>  - Target database name
--
-- Usage:
--   snow sql -f scripts/24_streamlit_stage_setup.sql -D "database=YOUR_DATABASE"
--
-- Note: After running this script, upload Streamlit files using:
--   snow stage copy streamlit/ @<database>.APPLICATIONS.STREAMLIT_STAGE --overwrite
--
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE SCHEMA APPLICATIONS;

-- =============================================================================
-- 1. CREATE STREAMLIT STAGE
-- =============================================================================

CREATE STAGE IF NOT EXISTS STREAMLIT_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for Streamlit application files';

-- =============================================================================
-- 2. CREATE SUBDIRECTORY FOR GEOSPATIAL APP
-- =============================================================================
-- The geospatial app has its own pyproject.toml and config, so it needs
-- a dedicated subdirectory in the stage

-- Note: Subdirectories are created automatically when files are uploaded
-- Use: snow stage copy streamlit/geospatial/ @STREAMLIT_STAGE/geospatial/ --overwrite

-- =============================================================================
-- VERIFY STAGE
-- =============================================================================

SHOW STAGES LIKE 'STREAMLIT_STAGE' IN SCHEMA APPLICATIONS;

-- List files (will be empty until upload)
-- LS @STREAMLIT_STAGE;

SELECT 
    'Stage created successfully. Upload files using:' AS instruction,
    'snow stage copy streamlit/ @' || '<% database %>' || '.APPLICATIONS.STREAMLIT_STAGE --overwrite --recursive' AS command;
