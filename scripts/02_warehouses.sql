-- =============================================================================
-- 02_warehouses.sql
-- Flux Utility Solutions - Compute Warehouse Setup
-- =============================================================================
-- Purpose: Create compute warehouses for different workloads
-- Jinja2 Variables:
--   <% database %>        - Target database name
--   <% warehouse %>       - Primary warehouse name
--   <% warehouse_size %>  - Warehouse size (XSMALL, SMALL, MEDIUM, LARGE)
--   <% admin_role %>      - Administrator role
--   <% user_role %>       - End-user role
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. PRIMARY WAREHOUSE (Analytics)
-- -----------------------------------------------------------------------------
-- Used for: Dashboard queries, Cortex Analyst, general analytics

CREATE OR ALTER WAREHOUSE IDENTIFIER('<% warehouse %>')
    WAREHOUSE_SIZE = '<% warehouse_size %>'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 2
    SCALING_POLICY = 'STANDARD'
    INITIALLY_SUSPENDED = FALSE
    COMMENT = 'Flux primary analytics warehouse';

-- Grant usage to roles
GRANT USAGE ON WAREHOUSE IDENTIFIER('<% warehouse %>') 
    TO ROLE IDENTIFIER('<% admin_role %>');

GRANT USAGE ON WAREHOUSE IDENTIFIER('<% warehouse %>') 
    TO ROLE IDENTIFIER('<% user_role %>');

-- -----------------------------------------------------------------------------
-- 2. LARGE WAREHOUSE (Heavy Analytics)
-- -----------------------------------------------------------------------------
-- Used for: AMI data processing (7.1B rows), ML training, bulk operations

CREATE OR ALTER WAREHOUSE IDENTIFIER('<% warehouse_ %>LARGE')
    WAREHOUSE_SIZE = 'LARGE'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 120
    AUTO_RESUME = TRUE
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 4
    SCALING_POLICY = 'ECONOMY'
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Flux large warehouse for heavy analytics (AMI, ML)';

GRANT USAGE ON WAREHOUSE IDENTIFIER('<% warehouse_ %>LARGE') 
    TO ROLE IDENTIFIER('<% admin_role %>');

-- -----------------------------------------------------------------------------
-- 3. LOADING WAREHOUSE (ETL)
-- -----------------------------------------------------------------------------
-- Used for: Data loading, Snowpipe, staging operations

CREATE OR ALTER WAREHOUSE IDENTIFIER('<% warehouse_ %>LOADING')
    WAREHOUSE_SIZE = 'SMALL'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 1
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Flux ETL warehouse for data loading';

GRANT USAGE ON WAREHOUSE IDENTIFIER('<% warehouse_ %>LOADING') 
    TO ROLE IDENTIFIER('<% admin_role %>');

-- -----------------------------------------------------------------------------
-- 4. CORTEX WAREHOUSE (AI Services)
-- -----------------------------------------------------------------------------
-- Used for: Cortex Search refresh, embedding generation

CREATE OR ALTER WAREHOUSE IDENTIFIER('<% warehouse_ %>CORTEX')
    WAREHOUSE_SIZE = 'MEDIUM'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 2
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Flux Cortex AI warehouse for search and embeddings';

GRANT USAGE ON WAREHOUSE IDENTIFIER('<% warehouse_ %>CORTEX') 
    TO ROLE IDENTIFIER('<% admin_role %>');

GRANT USAGE ON WAREHOUSE IDENTIFIER('<% warehouse_ %>CORTEX') 
    TO ROLE IDENTIFIER('<% user_role %>');

-- -----------------------------------------------------------------------------
-- 5. SET DEFAULT WAREHOUSE
-- -----------------------------------------------------------------------------

ALTER USER CURRENT_USER SET DEFAULT_WAREHOUSE = '<% warehouse %>';

-- -----------------------------------------------------------------------------
-- 6. VERIFICATION
-- -----------------------------------------------------------------------------

SHOW WAREHOUSES LIKE '<% warehouse %>%';

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 03_substations_transformers.sql to create grid foundation tables
-- =============================================================================
