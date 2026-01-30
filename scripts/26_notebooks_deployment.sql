-- =============================================================================
-- 26_notebooks_deployment.sql
-- Flux Utility Solutions - Snowflake Notebooks Deployment
-- =============================================================================
-- Purpose: Create stage and deploy Jupyter notebooks to Snowflake
-- Dependencies: Database and schemas (01)
-- 
-- Variable Templating (Snow CLI Jinja2):
--   <% database %>  - Target database name
--
-- Usage:
--   snow sql -f scripts/26_notebooks_deployment.sql -D "database=YOUR_DATABASE"
--
-- Note: After running this script, notebooks can be opened in Snowsight
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE SCHEMA APPLICATIONS;

-- =============================================================================
-- 1. CREATE NOTEBOOKS STAGE
-- =============================================================================

CREATE STAGE IF NOT EXISTS NOTEBOOKS_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for Snowflake Notebooks';

-- =============================================================================
-- 2. NOTEBOOK MANIFEST
-- =============================================================================
-- The following notebooks are included in this deployment:
--
-- SETUP NOTEBOOKS:
--   - setup/01_full_deployment.ipynb     : Complete infrastructure deployment
--   - setup/02_load_seed_data.ipynb      : Load sample data
--
-- DEMO NOTEBOOKS:
--   - demos/ami_analytics.ipynb          : AMI data exploration and analysis
--   - demos/transformer_risk_ml.ipynb    : ML-based transformer risk prediction
--   - demos/geospatial_h3.ipynb          : H3 hexagonal grid analytics
--   - demos/customer_360_search.ipynb    : Customer search with Cortex
--
-- ADVANCED NOTEBOOKS:
--   - advanced/cascade_simulation.ipynb  : Cascade failure simulation
--
-- SQL WORKSHEETS:
--   - explore_ami_data.sql               : AMI data exploration queries
--   - analysis_transformer_risk.sql      : Transformer risk analysis

-- =============================================================================
-- 3. CREATE NOTEBOOK OBJECTS (if supported)
-- =============================================================================
-- Note: Snowflake Notebooks are created via Snowsight UI or API
-- The stage serves as the source for notebook files

-- For Git Integration deployment, notebooks are copied from repo to stage:
-- COPY FILES INTO @NOTEBOOKS_STAGE
-- FROM @flux_utility_solutions_repo/branches/main/notebooks/;

-- =============================================================================
-- VERIFY STAGE
-- =============================================================================

SHOW STAGES LIKE 'NOTEBOOKS_STAGE' IN SCHEMA APPLICATIONS;

SELECT 
    'Notebooks stage created. Upload notebooks using:' AS instruction,
    'snow stage copy notebooks/ @' || '<% database %>' || '.APPLICATIONS.NOTEBOOKS_STAGE --recursive --overwrite' AS snow_cli_command;

-- =============================================================================
-- 4. DISPLAY AVAILABLE NOTEBOOKS
-- =============================================================================

SELECT 
    'SETUP' AS category,
    '01_full_deployment.ipynb' AS notebook,
    'Complete infrastructure deployment walkthrough' AS description
UNION ALL SELECT 'SETUP', '02_load_seed_data.ipynb', 'Load sample data for demos'
UNION ALL SELECT 'DEMO', 'ami_analytics.ipynb', 'AMI data exploration and analysis'
UNION ALL SELECT 'DEMO', 'transformer_risk_ml.ipynb', 'ML-based transformer risk prediction'
UNION ALL SELECT 'DEMO', 'geospatial_h3.ipynb', 'H3 hexagonal grid analytics'
UNION ALL SELECT 'DEMO', 'customer_360_search.ipynb', 'Customer search with Cortex'
UNION ALL SELECT 'ADVANCED', 'cascade_simulation.ipynb', 'Cascade failure simulation'
ORDER BY category, notebook;
