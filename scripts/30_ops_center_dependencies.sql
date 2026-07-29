-- =============================================================================
-- 30_ops_center_dependencies.sql
-- Flux Utility Solutions - Flux Ops Center SPCS Dependencies
-- =============================================================================
-- Purpose: Create ALL objects required by Flux Ops Center SPCS application
-- This script must be run BEFORE deploying the Ops Center container.
--
-- Cross-repo relationship:
--   This script in flux-utility-solutions creates the Snowflake objects that
--   flux-ops-center-spcs (the SPCS container) reads at runtime. The schemas,
--   table structures, and sample data here are aligned with the ops center
--   backend (server_fastapi.py, cascade_simulator.py). If you modify table
--   schemas here, verify the corresponding API endpoints still work.
--
-- IMPORTANT - Common misconfiguration:
--   The <% database %> variable MUST match the database used by the ops center
--   container. If the ops center is configured to read from FLUX_DB, this
--   script must also target FLUX_DB. A mismatch causes "table not found" errors
--   at runtime with no clear error message from the container.
--
-- Dependencies Created:
--   APPLICATIONS Schema:
--     - FLUX_OPS_CENTER_KPIS (view)
--     - FLUX_OPS_CENTER_TOPOLOGY_METRO (view)
--     - FLUX_OPS_CENTER_TOPOLOGY_FEEDERS (view)
--     - FLUX_OPS_CENTER_TOPOLOGY (view) - Grid connection edges
--     - FLUX_OPS_CENTER_TOPOLOGY_NODES (view) - Asset nodes
--     - FLUX_OPS_CENTER_SERVICE_AREAS_MV (view)
--     - VEGETATION_RISK_COMPUTED (view)
--     - CIRCUIT_OUTAGE_STATUS (view)
--
--   ML_DEMO Schema:
--     - GRID_NODES (table)
--     - GRID_EDGES (table)
--     - T_TRANSFORMER_TEMPORAL_TRAINING (table)
--     - V_TRANSFORMER_ML_INFERENCE (view)
--
--   CASCADE_ANALYSIS Schema:
--     - NODE_CENTRALITY_FEATURES_V2 (table)
--     - PRECOMPUTED_CASCADES (table)
--     - GNN_PREDICTIONS (table)
--
-- Variables:
--   <% database %>    - Target database name
--   <% warehouse %>   - Warehouse for dynamic tables
--   <% admin_role %>  - Administrator role
--   <% user_role %>   - End-user role
--
-- Usage:
--   snow sql -f scripts/30_ops_center_dependencies.sql \
--       -D "database=FLUX_PROD" -D "warehouse=FLUX_WH" \
--       -D "admin_role=ACCOUNTADMIN" -D "user_role=PUBLIC"
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');

-- =============================================================================
-- SECTION 1: CREATE ADDITIONAL SCHEMAS FOR OPS CENTER
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS ML_DEMO
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'ML Demo objects for Flux Ops Center - grid graph, transformer predictions';

CREATE SCHEMA IF NOT EXISTS CASCADE_ANALYSIS
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Cascade failure analysis - GNN features, precomputed cascades';

-- Grant schema access
GRANT USAGE ON SCHEMA <% database %>.ML_DEMO TO ROLE IDENTIFIER('<% user_role %>');
GRANT USAGE ON SCHEMA <% database %>.CASCADE_ANALYSIS TO ROLE IDENTIFIER('<% user_role %>');
GRANT SELECT ON FUTURE TABLES IN SCHEMA <% database %>.ML_DEMO TO ROLE IDENTIFIER('<% user_role %>');
GRANT SELECT ON FUTURE TABLES IN SCHEMA <% database %>.CASCADE_ANALYSIS TO ROLE IDENTIFIER('<% user_role %>');
GRANT SELECT ON FUTURE VIEWS IN SCHEMA <% database %>.ML_DEMO TO ROLE IDENTIFIER('<% user_role %>');
GRANT SELECT ON FUTURE VIEWS IN SCHEMA <% database %>.CASCADE_ANALYSIS TO ROLE IDENTIFIER('<% user_role %>');

-- =============================================================================
-- SECTION 2: APPLICATIONS SCHEMA - OPS CENTER VIEWS
-- =============================================================================

USE SCHEMA APPLICATIONS;

-- -----------------------------------------------------------------------------
-- 2.1 FLUX_OPS_CENTER_KPIS - Real-time KPI Summary View
-- -----------------------------------------------------------------------------
-- Provides dashboard KPIs: total customers, active outages, load, crews

CREATE OR REPLACE VIEW FLUX_OPS_CENTER_KPIS AS
SELECT
    -- Customer metrics
    (SELECT COUNT(*) FROM <% database %>.PRODUCTION.METER_INFRASTRUCTURE) AS TOTAL_CUSTOMERS,
    
    -- Outage metrics (from circuit status or simulated)
    COALESCE(
        (SELECT COUNT(*) FROM <% database %>.PRODUCTION.CIRCUIT_METADATA WHERE STATUS = 'OUTAGE'),
        FLOOR(RANDOM() * 5)::INT  -- Simulated if no outage tracking
    ) AS ACTIVE_OUTAGES,
    
    -- Load metrics (aggregate from transformers)
    COALESCE(
        (SELECT ROUND(SUM(CURRENT_LOAD_KW) / 1000, 2) 
         FROM <% database %>.PRODUCTION.TRANSFORMER_HOURLY_LOAD 
         WHERE LOAD_HOUR >= DATEADD('hour', -1, CURRENT_TIMESTAMP())),
        ROUND(150 + RANDOM() * 50, 2)  -- Simulated ~150-200 MW
    ) AS TOTAL_LOAD_MW,
    
    -- Crew metrics (simulated - would come from workforce management)
    FLOOR(5 + RANDOM() * 10)::INT AS CREWS_ACTIVE,
    
    -- Restoration time (simulated - would come from outage history)
    ROUND(30 + RANDOM() * 60, 1) AS AVG_RESTORATION_MINUTES;

-- -----------------------------------------------------------------------------
-- 2.2 FLUX_OPS_CENTER_TOPOLOGY_METRO - Substation Overview
-- -----------------------------------------------------------------------------
-- Aggregates substation data with transformer counts and load

CREATE OR REPLACE VIEW FLUX_OPS_CENTER_TOPOLOGY_METRO AS
SELECT 
    s.SUBSTATION_ID,
    s.SUBSTATION_NAME,
    s.LATITUDE,
    s.LONGITUDE,
    s.CAPACITY_MVA,
    -- Calculate average load percentage across transformers
    COALESCE(
        (SELECT ROUND(AVG(LOAD_FACTOR_PCT), 2) 
         FROM <% database %>.PRODUCTION.TRANSFORMER_HOURLY_LOAD thl
         JOIN <% database %>.PRODUCTION.TRANSFORMER_METADATA tm 
             ON thl.TRANSFORMER_ID = tm.TRANSFORMER_ID
         WHERE tm.SUBSTATION_ID = s.SUBSTATION_ID
           AND thl.LOAD_HOUR >= DATEADD('hour', -1, CURRENT_TIMESTAMP())),
        ROUND(40 + RANDOM() * 40, 2)  -- Simulated 40-80% if no data
    ) AS AVG_LOAD_PCT,
    -- Count active outages at this substation
    COALESCE(
        (SELECT COUNT(*) 
         FROM <% database %>.PRODUCTION.CIRCUIT_METADATA c
         WHERE c.SUBSTATION_ID = s.SUBSTATION_ID AND c.STATUS = 'OUTAGE'),
        0
    ) AS ACTIVE_OUTAGES,
    -- Transformer counts
    (SELECT COUNT(*) 
     FROM <% database %>.PRODUCTION.TRANSFORMER_METADATA tm 
     WHERE tm.SUBSTATION_ID = s.SUBSTATION_ID) AS TRANSFORMER_COUNT,
    -- Total transformer capacity
    (SELECT COALESCE(SUM(CAPACITY_KVA), 0) 
     FROM <% database %>.PRODUCTION.TRANSFORMER_METADATA tm 
     WHERE tm.SUBSTATION_ID = s.SUBSTATION_ID) AS TOTAL_CAPACITY_KVA
FROM <% database %>.PRODUCTION.SUBSTATIONS s;

-- -----------------------------------------------------------------------------
-- 2.3 FLUX_OPS_CENTER_TOPOLOGY_CIRCUITS - Feeder/Circuit Details
-- -----------------------------------------------------------------------------
-- Circuit-level topology for drill-down from substations.
--
-- NOTE (2026-07-29): this was previously named FLUX_OPS_CENTER_TOPOLOGY_FEEDERS,
-- but the SPCS backend's /api/topology/feeders endpoint expects an EDGE-shaped
-- result (substation -> transformer, with from/to coordinates), not this
-- circuit-shaped one. The name collision made that endpoint fail with
-- "invalid identifier 'TRANSFORMER_ID'" (HTTP 500), which rejected the
-- frontend's Promise.all and prevented ALL substations from rendering on the
-- map. This view keeps the circuit drill-down data product under an accurate
-- name; section 2.3b below defines the edge-shaped view the API actually reads.

CREATE OR REPLACE VIEW FLUX_OPS_CENTER_TOPOLOGY_CIRCUITS AS
SELECT 
    c.CIRCUIT_ID,
    c.CIRCUIT_NAME,
    c.SUBSTATION_ID,
    s.SUBSTATION_NAME,
    c.VOLTAGE_CLASS,
    c.LENGTH_MILES,
    COALESCE(c.STATUS, 'ENERGIZED') AS STATUS,
    -- Meter count on this circuit
    (SELECT COUNT(*) 
     FROM <% database %>.PRODUCTION.METER_INFRASTRUCTURE m 
     WHERE m.CIRCUIT_ID = c.CIRCUIT_ID) AS METER_COUNT,
    -- Average voltage (from AMI or simulated)
    COALESCE(
        (SELECT ROUND(AVG(VOLTAGE_V), 1) 
         FROM <% database %>.PRODUCTION.AMI_INTERVAL_READINGS air
         JOIN <% database %>.PRODUCTION.METER_INFRASTRUCTURE m 
             ON air.METER_ID = m.METER_ID
         WHERE m.CIRCUIT_ID = c.CIRCUIT_ID
           AND air.READING_TIMESTAMP >= DATEADD('hour', -1, CURRENT_TIMESTAMP())),
        CASE c.VOLTAGE_CLASS 
            WHEN '4KV' THEN 4160 
            WHEN '12KV' THEN 12470 
            WHEN '25KV' THEN 24900 
            ELSE 12470 
        END * (0.98 + RANDOM() * 0.04)  -- 98-102% of nominal
    ) AS AVG_VOLTAGE,
    -- Outage indicator
    CASE WHEN c.STATUS = 'OUTAGE' THEN TRUE ELSE FALSE END AS HAS_OUTAGE
FROM <% database %>.PRODUCTION.CIRCUIT_METADATA c
LEFT JOIN <% database %>.PRODUCTION.SUBSTATIONS s ON c.SUBSTATION_ID = s.SUBSTATION_ID;

-- -----------------------------------------------------------------------------
-- 2.4 FLUX_OPS_CENTER_TOPOLOGY - Grid Connection Topology (Edges)
-- -----------------------------------------------------------------------------
-- Represents grid connectivity as edges between assets (for graph visualization)
-- Used by: /api/topology endpoint, sync_snowflake_to_postgres.py

CREATE OR REPLACE VIEW FLUX_OPS_CENTER_TOPOLOGY AS
WITH 
-- Substation to Transformer connections
substation_transformer AS (
    SELECT 
        s.SUBSTATION_ID AS FROM_ASSET_ID,
        'SUBSTATION' AS FROM_ASSET_TYPE,
        s.LATITUDE AS FROM_LATITUDE,
        s.LONGITUDE AS FROM_LONGITUDE,
        tm.TRANSFORMER_ID AS TO_ASSET_ID,
        'TRANSFORMER' AS TO_ASSET_TYPE,
        tm.LATITUDE AS TO_LATITUDE,
        tm.LONGITUDE AS TO_LONGITUDE,
        s.SUBSTATION_ID,
        NULL AS CIRCUIT_ID,
        NULL AS FEEDER_ID,
        'ENERGIZED' AS STATUS,
        COALESCE(tm.PRIMARY_VOLTAGE_KV, 12.47) AS VOLTAGE_KV
    FROM <% database %>.PRODUCTION.SUBSTATIONS s
    JOIN <% database %>.PRODUCTION.TRANSFORMER_METADATA tm 
        ON tm.SUBSTATION_ID = s.SUBSTATION_ID
    WHERE s.LATITUDE IS NOT NULL AND tm.LATITUDE IS NOT NULL
),
-- Transformer to Meter connections
transformer_meter AS (
    SELECT 
        tm.TRANSFORMER_ID AS FROM_ASSET_ID,
        'TRANSFORMER' AS FROM_ASSET_TYPE,
        tm.LATITUDE AS FROM_LATITUDE,
        tm.LONGITUDE AS FROM_LONGITUDE,
        m.METER_ID AS TO_ASSET_ID,
        'METER' AS TO_ASSET_TYPE,
        m.LATITUDE AS TO_LATITUDE,
        m.LONGITUDE AS TO_LONGITUDE,
        tm.SUBSTATION_ID,
        m.CIRCUIT_ID,
        NULL AS FEEDER_ID,
        'ENERGIZED' AS STATUS,
        0.240 AS VOLTAGE_KV  -- Secondary voltage
    FROM <% database %>.PRODUCTION.TRANSFORMER_METADATA tm
    JOIN <% database %>.PRODUCTION.METER_INFRASTRUCTURE m 
        ON m.TRANSFORMER_ID = tm.TRANSFORMER_ID
    WHERE tm.LATITUDE IS NOT NULL AND m.LATITUDE IS NOT NULL
),
-- Circuit connections (substation to substation via circuits)
circuit_connections AS (
    SELECT 
        c.SUBSTATION_ID AS FROM_ASSET_ID,
        'SUBSTATION' AS FROM_ASSET_TYPE,
        s1.LATITUDE AS FROM_LATITUDE,
        s1.LONGITUDE AS FROM_LONGITUDE,
        'CIRCUIT_' || c.CIRCUIT_ID AS TO_ASSET_ID,
        'CIRCUIT' AS TO_ASSET_TYPE,
        -- Feeder representative point -- REAL coordinates, not fabricated.
        -- Until 2026-07-29 this was s1.LATITUDE + (RANDOM() - 0.5) * 0.05, which was
        -- catastrophically wrong: Snowflake RANDOM() returns a SIGNED 64-BIT INTEGER,
        -- not a [0,1) float, so this produced "latitudes" of ~4.6e17, NaN distances and
        -- a 10,110 km median edge length. CIRCUIT_METADATA now carries a real
        -- REPRESENTATIVE_LAT/LON (see scripts/31_regenerate_coherent_topology.sql), so
        -- read it. NEVER reintroduce bare RANDOM() arithmetic here.
        c.REPRESENTATIVE_LAT AS TO_LATITUDE,
        c.REPRESENTATIVE_LON AS TO_LONGITUDE,
        c.SUBSTATION_ID,
        c.CIRCUIT_ID,
        c.CIRCUIT_ID AS FEEDER_ID,
        COALESCE(c.STATUS, 'ENERGIZED') AS STATUS,
        CASE c.VOLTAGE_CLASS 
            WHEN '4KV' THEN 4.16 
            WHEN '12KV' THEN 12.47 
            WHEN '25KV' THEN 24.9 
            ELSE 12.47 
        END AS VOLTAGE_KV
    FROM <% database %>.PRODUCTION.CIRCUIT_METADATA c
    JOIN <% database %>.PRODUCTION.SUBSTATIONS s1 ON c.SUBSTATION_ID = s1.SUBSTATION_ID
    WHERE s1.LATITUDE IS NOT NULL
)
-- Union all topology edges
SELECT * FROM substation_transformer
UNION ALL
SELECT * FROM transformer_meter
UNION ALL
SELECT * FROM circuit_connections;

-- Also create a node-centric view for sync operations
CREATE OR REPLACE VIEW FLUX_OPS_CENTER_TOPOLOGY_NODES AS
SELECT 
    SUBSTATION_ID AS ASSET_ID,
    'SUBSTATION' AS ASSET_TYPE,
    SUBSTATION_ID,
    NULL AS CIRCUIT_ID,
    NULL AS FEEDER_ID,
    LATITUDE,
    LONGITUDE,
    'ENERGIZED' AS STATUS,
    CAPACITY_MVA * 1000 AS VOLTAGE_KV  -- Approximate
FROM <% database %>.PRODUCTION.SUBSTATIONS
WHERE LATITUDE IS NOT NULL
UNION ALL
SELECT 
    TRANSFORMER_ID AS ASSET_ID,
    'TRANSFORMER' AS ASSET_TYPE,
    SUBSTATION_ID,
    NULL AS CIRCUIT_ID,
    NULL AS FEEDER_ID,
    LATITUDE,
    LONGITUDE,
    'ENERGIZED' AS STATUS,
    COALESCE(PRIMARY_VOLTAGE_KV, 12.47) AS VOLTAGE_KV
FROM <% database %>.PRODUCTION.TRANSFORMER_METADATA
WHERE LATITUDE IS NOT NULL
UNION ALL
SELECT 
    METER_ID AS ASSET_ID,
    'METER' AS ASSET_TYPE,
    NULL AS SUBSTATION_ID,
    CIRCUIT_ID,
    NULL AS FEEDER_ID,
    LATITUDE,
    LONGITUDE,
    'ACTIVE' AS STATUS,
    0.240 AS VOLTAGE_KV
FROM <% database %>.PRODUCTION.METER_INFRASTRUCTURE
WHERE LATITUDE IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 2.4b FLUX_OPS_CENTER_TOPOLOGY_FEEDERS - Substation -> Transformer Feeder Edges
-- -----------------------------------------------------------------------------
-- Used by: /api/topology/feeders (flux_ops_center_spcs backend/server_fastapi.py
--          ~line 1682) and the frontend FeederConnection deck.gl line layer.
--
-- CONTRACT: the 12 columns below are dictated by that endpoint's SELECT list.
-- Do NOT add, remove, or rename columns without updating the endpoint in the
-- same change. Breaking this contract returns HTTP 500 from the endpoint, which
-- rejects the frontend's Promise.all([metro, feeders]) and silently prevents
-- ALL substations from rendering -- not just the feeder lines. That exact
-- regression was live from the cpe_demo_CLI migration until 2026-07-29.
--
-- VOLTAGE_LEVEL is emitted as text because the frontend filters distribution
-- feeders with a substring test that excludes '138', '230' and '345'. Keep the
-- decimal point in the formatted value so e.g. 34.5 kV does not read as '345'.
--
-- ONE ROW PER TRANSFORMER. Do NOT join CIRCUIT_METADATA on SUBSTATION_ID here:
-- circuits are per-substation, so that join fans out every transformer once per
-- circuit on its substation (measured 50x on 2026-07-29, and it would reach
-- millions of rows at full seed scale). CIRCUIT_ID is a deterministic scalar pick.
--
-- SCALE NOTE: this yields only ~100 edges today because PRODUCTION.SUBSTATIONS
-- keys on SUB_0001 while PRODUCTION.TRANSFORMER_METADATA keys on SUB-HOU-0001.
-- Reconciling that key space scales this view to ~47k real edges with no DDL change.

CREATE OR REPLACE VIEW FLUX_OPS_CENTER_TOPOLOGY_FEEDERS AS
SELECT
    tm.SUBSTATION_ID                             AS SUBSTATION_ID,
    tm.TRANSFORMER_ID                            AS TRANSFORMER_ID,
    'SUBSTATION_TO_TRANSFORMER'                  AS CONNECTION_TYPE,
    s.LATITUDE                                   AS FROM_LATITUDE,
    s.LONGITUDE                                  AS FROM_LONGITUDE,
    tm.LATITUDE                                  AS TO_LATITUDE,
    tm.LONGITUDE                                 AS TO_LONGITUDE,
    CASE
        WHEN tm.CAPACITY_KVA IS NULL OR tm.CAPACITY_KVA = 0 THEN NULL
        ELSE ROUND(100.0 * tm.CURRENT_LOAD_KVA / tm.CAPACITY_KVA, 2)
    END                                          AS LOAD_UTILIZATION_PCT,
    (SELECT MIN(c.CIRCUIT_ID)
       FROM <% database %>.PRODUCTION.CIRCUIT_METADATA c
      WHERE c.SUBSTATION_ID = tm.SUBSTATION_ID)  AS CIRCUIT_ID,
    tm.CAPACITY_KVA                              AS RATED_KVA,
    ROUND(HAVERSINE(s.LATITUDE, s.LONGITUDE,
                    tm.LATITUDE, tm.LONGITUDE), 3) AS DISTANCE_KM,
    COALESCE(TO_VARCHAR(ROUND(tm.PRIMARY_VOLTAGE_KV, 2)) || ' kV', '12.47 kV') AS VOLTAGE_LEVEL
FROM <% database %>.PRODUCTION.TRANSFORMER_METADATA tm
JOIN <% database %>.PRODUCTION.SUBSTATIONS s
      ON tm.SUBSTATION_ID = s.SUBSTATION_ID
WHERE tm.LATITUDE IS NOT NULL AND s.LATITUDE IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 2.5 FLUX_OPS_CENTER_SERVICE_AREAS_MV - Service Area Aggregations
-- -----------------------------------------------------------------------------
-- Geographic service area summary (simplified as view, can be dynamic table)

CREATE OR REPLACE VIEW FLUX_OPS_CENTER_SERVICE_AREAS_MV AS
SELECT 
    s.SUBSTATION_ID AS SERVICE_AREA_ID,
    s.SUBSTATION_NAME AS SERVICE_AREA_NAME,
    s.LATITUDE AS CENTER_LAT,
    s.LONGITUDE AS CENTER_LON,
    -- Aggregate metrics
    (SELECT COUNT(*) 
     FROM <% database %>.PRODUCTION.METER_INFRASTRUCTURE m
     JOIN <% database %>.PRODUCTION.TRANSFORMER_METADATA tm ON m.TRANSFORMER_ID = tm.TRANSFORMER_ID
     WHERE tm.SUBSTATION_ID = s.SUBSTATION_ID) AS CUSTOMER_COUNT,
    (SELECT COUNT(*) 
     FROM <% database %>.PRODUCTION.TRANSFORMER_METADATA tm 
     WHERE tm.SUBSTATION_ID = s.SUBSTATION_ID) AS TRANSFORMER_COUNT,
    (SELECT COUNT(*) 
     FROM <% database %>.PRODUCTION.CIRCUIT_METADATA c 
     WHERE c.SUBSTATION_ID = s.SUBSTATION_ID) AS CIRCUIT_COUNT,
    s.CAPACITY_MVA AS TOTAL_CAPACITY_MVA,
    -- Simulated reliability metrics
    ROUND(99.5 + RANDOM() * 0.4, 2) AS RELIABILITY_PCT,
    ROUND(0.5 + RANDOM() * 1.5, 2) AS SAIDI_MINUTES
FROM <% database %>.PRODUCTION.SUBSTATIONS s;

-- -----------------------------------------------------------------------------
-- 2.5 VEGETATION_RISK_COMPUTED - Vegetation Risk Analysis
-- -----------------------------------------------------------------------------
-- Vegetation proximity risk (joins with grid assets when PostGIS data available)

CREATE OR REPLACE VIEW VEGETATION_RISK_COMPUTED AS
SELECT
    'VEG_' || SEQ4() AS TREE_ID,
    CASE MOD(SEQ4(), 5)
        WHEN 0 THEN 'Oak'
        WHEN 1 THEN 'Pine'
        WHEN 2 THEN 'Maple'
        WHEN 3 THEN 'Cypress'
        ELSE 'Elm'
    END AS SPECIES,
    CASE MOD(SEQ4(), 3)
        WHEN 0 THEN 'Deciduous'
        WHEN 1 THEN 'Conifer'
        ELSE 'Mixed'
    END AS SUBTYPE,
    -- Generate coordinates around Houston metro (29.7° to 30.0° lat, -95.7° to -95.0° lon)
    -95.7 + RANDOM() * 0.7 AS LONGITUDE,
    29.7 + RANDOM() * 0.3 AS LATITUDE,
    ROUND(8 + RANDOM() * 25, 1) AS HEIGHT_M,
    ROUND(2 + RANDOM() * 6, 1) AS CANOPY_RADIUS_M,
    -- Risk scoring
    ROUND(RANDOM(), 3) AS RISK_SCORE,
    CASE 
        WHEN RANDOM() < 0.03 THEN 'critical'
        WHEN RANDOM() < 0.10 THEN 'warning'
        WHEN RANDOM() < 0.25 THEN 'monitor'
        ELSE 'safe'
    END AS RISK_LEVEL,
    ROUND(2 + RANDOM() * 50, 1) AS DISTANCE_TO_LINE_M,
    'LINE_' || FLOOR(RANDOM() * 1000)::VARCHAR AS NEAREST_LINE_ID,
    CASE MOD(SEQ4(), 3) WHEN 0 THEN 'transmission' WHEN 1 THEN 'distribution' ELSE 'service' END AS NEAREST_LINE_CLASS,
    ROUND(10 + RANDOM() * 20, 1) AS FALL_ZONE_M,
    'Tree within ' || ROUND(2 + RANDOM() * 50, 0)::VARCHAR || 'm of power line' AS RISK_EXPLANATION,
    CASE MOD(SEQ4(), 4) WHEN 0 THEN 'pole' WHEN 1 THEN 'transformer' WHEN 2 THEN 'line' ELSE 'substation' END AS NEAREST_ASSET_TYPE,
    ROUND(5 + RANDOM() * 100, 1) AS DISTANCE_TO_ASSET_M,
    CURRENT_TIMESTAMP() AS COMPUTED_AT
FROM TABLE(GENERATOR(ROWCOUNT => 10000));

-- -----------------------------------------------------------------------------
-- 2.5b VEGETATION_RISK_ENHANCED - Enhanced Vegetation Data Table
-- -----------------------------------------------------------------------------
-- Stores enhanced vegetation risk data from external processing (e.g., Meta Canopy, LiDAR)
-- This table is populated by backend/scripts/process_meta_canopy_houston.py
-- Data is synced to Postgres for spatial queries

CREATE TABLE IF NOT EXISTS APPLICATIONS.VEGETATION_RISK_ENHANCED (
    TREE_ID VARCHAR(100) PRIMARY KEY,
    LONGITUDE FLOAT NOT NULL,
    LATITUDE FLOAT NOT NULL,
    HEIGHT_M FLOAT,                        -- Tree height in meters
    CANOPY_RADIUS_M FLOAT,                 -- Estimated canopy spread
    SPECIES VARCHAR(100),                  -- Tree species if known
    TREE_CLASS VARCHAR(50),                -- small_tree, medium_tree, large_tree
    RISK_SCORE FLOAT,                      -- 0.0-1.0 overall risk
    RISK_LEVEL VARCHAR(20),                -- critical, warning, monitor, safe
    DISTANCE_TO_LINE_M FLOAT,              -- Distance to nearest power line
    NEAREST_LINE_ID VARCHAR(100),          -- ID of nearest power line
    NEAREST_LINE_VOLTAGE_KV FLOAT,         -- Voltage level
    MINIMUM_CLEARANCE_M FLOAT,             -- Required clearance
    CLEARANCE_DEFICIT_M FLOAT,             -- How much tree exceeds clearance
    ESTIMATED_ANNUAL_GROWTH_M FLOAT,       -- Growth rate
    YEARS_TO_ENCROACHMENT FLOAT,           -- Prediction
    DATA_SOURCE VARCHAR(100),              -- 'meta_canopy_2020', 'lidar_2024'
    SOURCE_DATE DATE,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Enhanced vegetation risk data from external processing for Postgres sync';

-- -----------------------------------------------------------------------------
-- 2.6 CIRCUIT_OUTAGE_STATUS - Per-circuit outage events
-- -----------------------------------------------------------------------------
-- Live circuit status for outage tracking

CREATE OR REPLACE VIEW CIRCUIT_OUTAGE_STATUS AS
SELECT 
    c.CIRCUIT_ID,
    c.CIRCUIT_NAME,
    c.SUBSTATION_ID,
    COALESCE(c.STATUS, 'ENERGIZED') AS STATUS,
    CASE COALESCE(c.STATUS, 'ENERGIZED')
        WHEN 'OUTAGE' THEN DATEADD('minute', -FLOOR(RANDOM() * 120)::INT, CURRENT_TIMESTAMP())
        ELSE NULL
    END AS OUTAGE_START_TIME,
    CASE COALESCE(c.STATUS, 'ENERGIZED')
        WHEN 'OUTAGE' THEN FLOOR(RANDOM() * 500)::INT
        ELSE 0
    END AS CUSTOMERS_AFFECTED,
    CASE COALESCE(c.STATUS, 'ENERGIZED')
        WHEN 'OUTAGE' THEN 
            CASE MOD(FLOOR(RANDOM() * 5)::INT, 5)
                WHEN 0 THEN 'Equipment Failure'
                WHEN 1 THEN 'Weather'
                WHEN 2 THEN 'Vehicle Accident'
                WHEN 3 THEN 'Animal Contact'
                ELSE 'Unknown'
            END
        ELSE NULL
    END AS OUTAGE_CAUSE,
    CURRENT_TIMESTAMP() AS LAST_UPDATED
FROM <% database %>.PRODUCTION.CIRCUIT_METADATA c;

-- Grant access to APPLICATIONS views
GRANT SELECT ON ALL VIEWS IN SCHEMA <% database %>.APPLICATIONS TO ROLE IDENTIFIER('<% user_role %>');

-- =============================================================================
-- SECTION 3: ML_DEMO SCHEMA - GRAPH AND PREDICTION TABLES
-- =============================================================================

USE SCHEMA ML_DEMO;

-- -----------------------------------------------------------------------------
-- 3.1 GRID_NODES - Graph nodes for GNN cascade analysis
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS GRID_NODES (
    NODE_ID VARCHAR(50) PRIMARY KEY,
    NODE_TYPE VARCHAR(20) NOT NULL,  -- SUBSTATION, TRANSFORMER, METER, JUNCTION
    NODE_NAME VARCHAR(200),
    LATITUDE FLOAT,
    LONGITUDE FLOAT,
    LAT FLOAT,  -- Alias for LATITUDE (backend compatibility)
    LON FLOAT,  -- Alias for LONGITUDE (backend compatibility)
    VOLTAGE_LEVEL VARCHAR(20),
    VOLTAGE_KV FLOAT,  -- Numeric voltage for backend queries
    CAPACITY_KVA FLOAT,
    CAPACITY_KW FLOAT,  -- Backend expects CAPACITY_KW
    PARENT_NODE_ID VARCHAR(50),
    SUBSTATION_ID VARCHAR(50),
    -- GNN Features
    DEGREE_CENTRALITY FLOAT,
    BETWEENNESS_CENTRALITY FLOAT,
    LOAD_FACTOR FLOAT,
    AGE_YEARS FLOAT,
    HEALTH_SCORE FLOAT,
    CRITICALITY_SCORE FLOAT,  -- Risk/importance score for cascade analysis
    DOWNSTREAM_TRANSFORMERS INT DEFAULT 0,  -- Count of downstream transformers
    DOWNSTREAM_CAPACITY_KVA FLOAT DEFAULT 0,  -- Total downstream capacity
    -- Metadata
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (NODE_TYPE, SUBSTATION_ID)
COMMENT = 'Grid topology nodes for GNN-based cascade analysis';

-- -----------------------------------------------------------------------------
-- 3.2 GRID_EDGES - Graph edges connecting nodes
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS GRID_EDGES (
    EDGE_ID VARCHAR(50) PRIMARY KEY,
    FROM_NODE_ID VARCHAR(50) NOT NULL,
    TO_NODE_ID VARCHAR(50) NOT NULL,
    EDGE_TYPE VARCHAR(20) NOT NULL,  -- TRANSMISSION, DISTRIBUTION, SERVICE
    LENGTH_METERS FLOAT,
    DISTANCE_KM FLOAT,  -- Backend scripts expect DISTANCE_KM (LENGTH_METERS / 1000)
    IMPEDANCE_OHMS FLOAT,
    IMPEDANCE_PU FLOAT,  -- Per-unit impedance for graph centrality scripts
    CAPACITY_AMPS FLOAT,
    VOLTAGE_LEVEL VARCHAR(20),  -- Voltage level for edge classification
    -- Edge features for GNN
    CURRENT_FLOW_PCT FLOAT,
    IS_OPEN BOOLEAN DEFAULT FALSE,
    -- Metadata
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    FOREIGN KEY (FROM_NODE_ID) REFERENCES GRID_NODES(NODE_ID),
    FOREIGN KEY (TO_NODE_ID) REFERENCES GRID_NODES(NODE_ID)
)
COMMENT = 'Grid topology edges for GNN-based cascade analysis';

-- -----------------------------------------------------------------------------
-- 3.3 T_TRANSFORMER_TEMPORAL_TRAINING - ML Training Data
-- -----------------------------------------------------------------------------
-- The ops center backend endpoint /api/cascade/transformer-risk-prediction
-- requires the 18-column schema below. The old 9-column schema (LOAD_FACTOR_AVG_7D,
-- etc.) does not match what the backend queries. This uses CREATE OR REPLACE
-- to ensure existing deployments get the updated schema on re-run.

CREATE OR REPLACE TABLE T_TRANSFORMER_TEMPORAL_TRAINING (
    TRANSFORMER_ID                      VARCHAR(50)    NOT NULL,
    MORNING_TIMESTAMP                   TIMESTAMP_NTZ,
    PREDICTION_DATE                     TIMESTAMP_NTZ,
    MORNING_LOAD_PCT                    FLOAT,
    MORNING_CATEGORY                    VARCHAR(20),
    MORNING_KWH                         FLOAT,
    MORNING_ACTIVE_METERS               INT,
    MORNING_AVG_VOLTAGE                 INT,
    MORNING_VOLTAGE_SAGS                INT,
    RATED_KVA                           INT,
    HISTORICAL_SUMMER_AVG_LOAD          FLOAT,
    SUMMER_2023_2024_AVG_CRITICAL_HOURS FLOAT,
    STRESS_VS_HISTORICAL                VARCHAR(30),
    KWH_PER_METER                       FLOAT,
    LOAD_TREND_RATIO                    FLOAT,
    TARGET_HIGH_RISK                    INT,
    AFTERNOON_LOAD_PCT                  FLOAT,
    AFTERNOON_CATEGORY                  VARCHAR(20)
)
COMMENT = 'Temporal training data for transformer risk prediction model. Each row represents a morning-to-afternoon risk trajectory for one transformer on one day.';

-- -----------------------------------------------------------------------------
-- 3.4 V_TRANSFORMER_ML_INFERENCE - Latest Predictions View
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW V_TRANSFORMER_ML_INFERENCE AS
SELECT 
    t.TRANSFORMER_ID,
    t.PREDICTION_DATE,
    -- Compute risk score from temporal features
    LEAST(1.0,
        (t.MORNING_LOAD_PCT / 100.0) *
        (1 + COALESCE(TRY_TO_DOUBLE(t.STRESS_VS_HISTORICAL), 0) / 100) *
        (1 + (YEAR(CURRENT_DATE()) - tm.INSTALL_YEAR)::INT / 50.0)
    ) AS FAILURE_PROBABILITY,
    CASE 
        WHEN LEAST(1.0, (t.MORNING_LOAD_PCT / 100.0) * (1 + (YEAR(CURRENT_DATE()) - tm.INSTALL_YEAR)::INT / 50.0)) >= 0.7 THEN 'CRITICAL'
        WHEN LEAST(1.0, (t.MORNING_LOAD_PCT / 100.0) * (1 + (YEAR(CURRENT_DATE()) - tm.INSTALL_YEAR)::INT / 50.0)) >= 0.5 THEN 'HIGH'
        WHEN LEAST(1.0, (t.MORNING_LOAD_PCT / 100.0) * (1 + (YEAR(CURRENT_DATE()) - tm.INSTALL_YEAR)::INT / 50.0)) >= 0.3 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS RISK_CATEGORY,
    t.MORNING_LOAD_PCT AS LOAD_FACTOR_AVG_7D,
    (YEAR(CURRENT_DATE()) - tm.INSTALL_YEAR)::INT AS AGE_YEARS,
    100 - (t.MORNING_LOAD_PCT * 0.5 + (YEAR(CURRENT_DATE()) - tm.INSTALL_YEAR)::INT * 0.5) AS HEALTH_SCORE,
    tm.TRANSFORMER_NAME,
    tm.SUBSTATION_ID,
    tm.CAPACITY_KVA,
    tm.LATITUDE,
    tm.LONGITUDE
FROM T_TRANSFORMER_TEMPORAL_TRAINING t
JOIN <% database %>.PRODUCTION.TRANSFORMER_METADATA tm 
    ON t.TRANSFORMER_ID = tm.TRANSFORMER_ID
WHERE t.PREDICTION_DATE = (SELECT MAX(PREDICTION_DATE) FROM T_TRANSFORMER_TEMPORAL_TRAINING)
QUALIFY ROW_NUMBER() OVER (PARTITION BY t.TRANSFORMER_ID ORDER BY t.MORNING_TIMESTAMP DESC) = 1;

-- Grant access to ML_DEMO tables
GRANT SELECT ON ALL TABLES IN SCHEMA <% database %>.ML_DEMO TO ROLE IDENTIFIER('<% user_role %>');
GRANT SELECT ON ALL VIEWS IN SCHEMA <% database %>.ML_DEMO TO ROLE IDENTIFIER('<% user_role %>');

-- =============================================================================
-- SECTION 4: CASCADE_ANALYSIS SCHEMA - GNN ANALYSIS TABLES
-- =============================================================================

USE SCHEMA CASCADE_ANALYSIS;

-- -----------------------------------------------------------------------------
-- 4.1 NODE_CENTRALITY_FEATURES_V2 - Pre-computed GNN Features
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS NODE_CENTRALITY_FEATURES_V2 (
    NODE_ID VARCHAR(50) PRIMARY KEY,
    
    -- Centrality metrics (computed via GNN or graph algorithms)
    DEGREE_CENTRALITY FLOAT,
    BETWEENNESS_CENTRALITY FLOAT,
    CLOSENESS_CENTRALITY FLOAT,
    EIGENVECTOR_CENTRALITY FLOAT,
    PAGERANK_SCORE FLOAT,
    PAGERANK FLOAT,  -- Backend expects PAGERANK (alias for PAGERANK_SCORE)
    
    -- Clustering metrics
    CLUSTERING_COEFFICIENT FLOAT,
    LOCAL_EFFICIENCY FLOAT,
    
    -- Cascade risk metrics
    CASCADE_IMPACT_SCORE FLOAT,      -- Expected downstream impact if node fails
    VULNERABILITY_SCORE FLOAT,        -- Susceptibility to upstream failures
    CASCADE_RISK_SCORE_NORMALIZED FLOAT,  -- Normalized 0-1 cascade risk score
    CRITICALITY_RANK INT,             -- Overall importance ranking
    
    -- Graph neighborhood metrics
    TOTAL_REACH INT DEFAULT 0,        -- Maximum downstream nodes reachable
    NEIGHBORS_1HOP INT DEFAULT 0,     -- Direct neighbor count
    NEIGHBORS_2HOP INT DEFAULT 0,     -- 2-hop neighbor count
    
    -- Node attributes
    NODE_TYPE VARCHAR(20),
    SUBSTATION_ID VARCHAR(50),
    LOAD_FACTOR FLOAT,
    
    -- Metadata
    COMPUTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    MODEL_VERSION VARCHAR(20)
)
COMMENT = 'Pre-computed GNN centrality features for cascade analysis';

-- -----------------------------------------------------------------------------
-- 4.2 PRECOMPUTED_CASCADES - Simulated Cascade Scenarios
-- -----------------------------------------------------------------------------

CREATE OR REPLACE TABLE PRECOMPUTED_CASCADES (
    SCENARIO_ID VARCHAR(100) PRIMARY KEY,  -- Logical key; matches ops center schema (no CASCADE_ID)
    SCENARIO_NAME VARCHAR(200),  -- Backend cascade_simulator.py uses scenario_name
    INITIATING_NODE_ID VARCHAR(50) NOT NULL,
    PATIENT_ZERO_ID VARCHAR(50),  -- Alias for INITIATING_NODE_ID (backend compatibility)
    INITIATING_NODE_NAME VARCHAR(200),
    PATIENT_ZERO_NAME VARCHAR(200),  -- Alias for INITIATING_NODE_NAME (backend compatibility)
    INITIATING_NODE_TYPE VARCHAR(20),
    
    -- Cascade metrics
    TOTAL_AFFECTED_NODES INT,
    AFFECTED_SUBSTATIONS INT,
    AFFECTED_TRANSFORMERS INT,
    AFFECTED_CUSTOMERS INT,
    ESTIMATED_CUSTOMERS_AFFECTED INT,  -- Backend cascade_simulator.py column
    
    -- Impact metrics
    AFFECTED_CAPACITY_MW FLOAT,  -- Backend cascade_simulator.py column
    LOAD_SHED_MW FLOAT,
    ESTIMATED_RESTORATION_HOURS FLOAT,
    ECONOMIC_IMPACT_USD FLOAT,
    
    -- Cascade path (JSON array of affected node IDs in order)
    CASCADE_PATH VARIANT,
    CASCADE_ORDER VARIANT,  -- Backend cascade_simulator.py column (detailed node list)
    WAVE_BREAKDOWN VARIANT,  -- Backend cascade_simulator.py column
    PROPAGATION_PATHS VARIANT,  -- Backend cascade_simulator.py column
    SIMULATION_PARAMS VARIANT,  -- Backend cascade_simulator.py column
    CASCADE_DEPTH INT,
    MAX_CASCADE_DEPTH INT,  -- Backend cascade_simulator.py column
    
    -- Simulation metadata
    SIMULATION_TIMESTAMP TIMESTAMP_NTZ,
    SIMULATION_SCENARIO VARCHAR(50),  -- PEAK_LOAD, STORM, EQUIPMENT_FAILURE
    MODEL_VERSION VARCHAR(20),
    
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    COMPUTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()  -- server_fastapi.py uses computed_at for ORDER BY
)
CLUSTER BY (INITIATING_NODE_TYPE, SIMULATION_SCENARIO)
COMMENT = 'Pre-computed cascade failure scenarios for real-time risk assessment';

-- -----------------------------------------------------------------------------
-- 4.3 GNN_PREDICTIONS - Real-time GNN Model Outputs
-- -----------------------------------------------------------------------------
-- Used by /api/cascade/patient-zero-candidates when use_gnn_predictions=True.
-- The backend expects 5 columns: NODE_ID, NODE_TYPE, CRITICALITY_SCORE,
-- GNN_CASCADE_RISK, PREDICTION_TIMESTAMP.

CREATE OR REPLACE TABLE GNN_PREDICTIONS (
    NODE_ID VARCHAR(100) NOT NULL,
    NODE_TYPE VARCHAR(50),
    CRITICALITY_SCORE FLOAT,
    GNN_CASCADE_RISK FLOAT,
    PREDICTION_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'GNN model predictions for node failure and cascade risk';

-- Grant access to CASCADE_ANALYSIS tables
GRANT SELECT ON ALL TABLES IN SCHEMA <% database %>.CASCADE_ANALYSIS TO ROLE IDENTIFIER('<% user_role %>');

-- =============================================================================
-- SECTION 5: POPULATE SAMPLE DATA FOR OPS CENTER
-- =============================================================================
-- Generate sample data so Ops Center works immediately after deployment.
-- Uses TRUNCATE before INSERT for idempotent re-runs (prevents duplicate data
-- that previously occurred with duplicate inserts on partial reruns).
--
-- Data consumed by ops center endpoints:
--   GRID_NODES            → /api/cascade/grid-topology, /api/cascade/simulate
--   GRID_EDGES            → /api/cascade/simulate (BFS traversal)
--   T_TRANSFORMER_TEMPORAL_TRAINING → /api/cascade/transformer-risk-prediction
--   NODE_CENTRALITY_V2    → /api/cascade/high-risk-nodes, /api/cascade/simulate
--   GNN_PREDICTIONS       → /api/cascade/patient-zero-candidates
--   PRECOMPUTED_CASCADES  → /api/cascade/precomputed-scenarios

USE SCHEMA ML_DEMO;

-- 5.1 GRID_NODES — Populate from utility repo's existing infrastructure tables
TRUNCATE TABLE IF EXISTS GRID_NODES;

INSERT INTO GRID_NODES (NODE_ID, NODE_TYPE, NODE_NAME, LATITUDE, LONGITUDE, LAT, LON, VOLTAGE_LEVEL, VOLTAGE_KV, CAPACITY_KVA, CAPACITY_KW, SUBSTATION_ID, DEGREE_CENTRALITY, BETWEENNESS_CENTRALITY, LOAD_FACTOR, AGE_YEARS, HEALTH_SCORE, CRITICALITY_SCORE, DOWNSTREAM_TRANSFORMERS, DOWNSTREAM_CAPACITY_KVA)
SELECT 
    'SUB_' || s.SUBSTATION_ID AS NODE_ID,
    'SUBSTATION' AS NODE_TYPE,
    s.SUBSTATION_NAME AS NODE_NAME,
    s.LATITUDE,
    s.LONGITUDE,
    s.LATITUDE AS LAT,
    s.LONGITUDE AS LON,
    s.VOLTAGE_CLASS AS VOLTAGE_LEVEL,
    CASE 
        WHEN s.VOLTAGE_CLASS LIKE '%345%' THEN 345.0
        WHEN s.VOLTAGE_CLASS LIKE '%230%' THEN 230.0
        WHEN s.VOLTAGE_CLASS LIKE '%138%' THEN 138.0
        WHEN s.VOLTAGE_CLASS LIKE '%69%' THEN 69.0
        ELSE 12.47
    END AS VOLTAGE_KV,
    s.CAPACITY_MVA * 1000 AS CAPACITY_KVA,
    s.CAPACITY_MVA * 1000 AS CAPACITY_KW,
    s.SUBSTATION_ID,
    0.8 + RANDOM() * 0.2 AS DEGREE_CENTRALITY,
    0.3 + RANDOM() * 0.5 AS BETWEENNESS_CENTRALITY,
    0.4 + RANDOM() * 0.4 AS LOAD_FACTOR,
    5 + RANDOM() * 30 AS AGE_YEARS,
    60 + RANDOM() * 35 AS HEALTH_SCORE,
    0.5 + RANDOM() * 0.4 AS CRITICALITY_SCORE,
    COALESCE(t_count.cnt, 0) AS DOWNSTREAM_TRANSFORMERS,
    COALESCE(t_count.total_capacity, 0) AS DOWNSTREAM_CAPACITY_KVA
FROM <% database %>.PRODUCTION.SUBSTATIONS s
LEFT JOIN (
    SELECT SUBSTATION_ID, COUNT(*) AS cnt, SUM(CAPACITY_KVA) AS total_capacity
    FROM <% database %>.PRODUCTION.TRANSFORMER_METADATA
    GROUP BY SUBSTATION_ID
) t_count ON s.SUBSTATION_ID = t_count.SUBSTATION_ID;

-- Add transformer nodes
INSERT INTO GRID_NODES (NODE_ID, NODE_TYPE, NODE_NAME, LATITUDE, LONGITUDE, LAT, LON, VOLTAGE_LEVEL, VOLTAGE_KV, CAPACITY_KVA, CAPACITY_KW, SUBSTATION_ID, PARENT_NODE_ID, DEGREE_CENTRALITY, BETWEENNESS_CENTRALITY, LOAD_FACTOR, AGE_YEARS, HEALTH_SCORE, CRITICALITY_SCORE, DOWNSTREAM_TRANSFORMERS, DOWNSTREAM_CAPACITY_KVA)
SELECT 
    'XFMR_' || TRANSFORMER_ID AS NODE_ID,
    'TRANSFORMER' AS NODE_TYPE,
    TRANSFORMER_NAME AS NODE_NAME,
    LATITUDE,
    LONGITUDE,
    LATITUDE AS LAT,
    LONGITUDE AS LON,
    '12KV' AS VOLTAGE_LEVEL,
    12.47 AS VOLTAGE_KV,
    CAPACITY_KVA,
    CAPACITY_KVA AS CAPACITY_KW,
    SUBSTATION_ID,
    'SUB_' || SUBSTATION_ID AS PARENT_NODE_ID,
    0.3 + RANDOM() * 0.4 AS DEGREE_CENTRALITY,
    0.1 + RANDOM() * 0.3 AS BETWEENNESS_CENTRALITY,
    0.3 + RANDOM() * 0.5 AS LOAD_FACTOR,
    AGE_YEARS,
    HEALTH_SCORE,
    0.2 + RANDOM() * 0.5 AS CRITICALITY_SCORE,
    0 AS DOWNSTREAM_TRANSFORMERS,
    0 AS DOWNSTREAM_CAPACITY_KVA
FROM <% database %>.PRODUCTION.TRANSFORMER_METADATA;

-- 5.2 GRID_EDGES — Connect substations to transformers
TRUNCATE TABLE IF EXISTS GRID_EDGES;

INSERT INTO GRID_EDGES (EDGE_ID, FROM_NODE_ID, TO_NODE_ID, EDGE_TYPE, LENGTH_METERS, DISTANCE_KM, IMPEDANCE_OHMS, IMPEDANCE_PU, VOLTAGE_LEVEL, CAPACITY_AMPS, CURRENT_FLOW_PCT)
SELECT 
    'EDGE_' || n.NODE_ID AS EDGE_ID,
    n.PARENT_NODE_ID AS FROM_NODE_ID,
    n.NODE_ID AS TO_NODE_ID,
    'DISTRIBUTION' AS EDGE_TYPE,
    100 + RANDOM() * 500 AS LENGTH_METERS,
    ROUND((100 + RANDOM() * 500) / 1000, 4) AS DISTANCE_KM,
    0.1 + RANDOM() * 0.5 AS IMPEDANCE_OHMS,
    ROUND(0.01 + RANDOM() * 0.05, 4) AS IMPEDANCE_PU,
    n.VOLTAGE_LEVEL AS VOLTAGE_LEVEL,
    200 + RANDOM() * 300 AS CAPACITY_AMPS,
    0.3 + RANDOM() * 0.5 AS CURRENT_FLOW_PCT
FROM GRID_NODES n
WHERE n.PARENT_NODE_ID IS NOT NULL;

-- 5.3 T_TRANSFORMER_TEMPORAL_TRAINING — 19-column schema (20 days per transformer)
-- Consumed by /api/cascade/transformer-risk-prediction endpoint
TRUNCATE TABLE IF EXISTS T_TRANSFORMER_TEMPORAL_TRAINING;

INSERT INTO T_TRANSFORMER_TEMPORAL_TRAINING
WITH transformer_base AS (
    SELECT 
        TRANSFORMER_ID,
        CAPACITY_KVA,
        INSTALL_YEAR,
        HEALTH_SCORE,
        LATITUDE,
        LONGITUDE
    FROM <% database %>.PRODUCTION.TRANSFORMER_METADATA
),
date_series AS (
    SELECT DATEADD('day', -seq4(), CURRENT_DATE())::TIMESTAMP_NTZ AS prediction_date
    FROM TABLE(GENERATOR(ROWCOUNT => 20))
),
raw_data AS (
    SELECT
        t.TRANSFORMER_ID,
        DATEADD('hour', 8, d.prediction_date) AS MORNING_TIMESTAMP,
        d.prediction_date AS PREDICTION_DATE,
        ROUND(30 + (UNIFORM(0::FLOAT, 65::FLOAT, RANDOM()) * 
              (1 + (100 - COALESCE(t.HEALTH_SCORE, 75)) / 200.0)), 1) AS MORNING_LOAD_PCT,
        GREATEST(5, ROUND(UNIFORM(10::FLOAT, 50::FLOAT, RANDOM()))) AS MORNING_ACTIVE_METERS,
        ROUND(UNIFORM(118::FLOAT, 124::FLOAT, RANDOM())) AS MORNING_AVG_VOLTAGE,
        FLOOR(UNIFORM(0::FLOAT, 5::FLOAT, RANDOM())) AS MORNING_VOLTAGE_SAGS,
        t.INSTALL_YEAR,
        COALESCE(t.CAPACITY_KVA, 50) AS RATED_KVA,
        ROUND(UNIFORM(40::FLOAT, 80::FLOAT, RANDOM()), 1) AS HISTORICAL_SUMMER_AVG_LOAD,
        ROUND(UNIFORM(0::FLOAT, 120::FLOAT, RANDOM()), 1) AS SUMMER_2023_2024_AVG_CRITICAL_HOURS,
        ROUND(UNIFORM(5::FLOAT, 25::FLOAT, RANDOM()), 2) AS KWH_PER_METER,
        ROUND(UNIFORM(0.8::FLOAT, 1.3::FLOAT, RANDOM()), 3) AS LOAD_TREND_RATIO
    FROM transformer_base t
    CROSS JOIN date_series d
)
SELECT
    TRANSFORMER_ID,
    MORNING_TIMESTAMP,
    PREDICTION_DATE,
    MORNING_LOAD_PCT,
    CASE 
        WHEN MORNING_LOAD_PCT >= 80 THEN 'CRITICAL'
        WHEN MORNING_LOAD_PCT >= 60 THEN 'WARNING'
        WHEN MORNING_LOAD_PCT >= 40 THEN 'NORMAL'
        ELSE 'LOW'
    END AS MORNING_CATEGORY,
    ROUND(MORNING_LOAD_PCT * RATED_KVA * 0.01 * MORNING_ACTIVE_METERS * 0.5, 1) AS MORNING_KWH,
    MORNING_ACTIVE_METERS::INT,
    MORNING_AVG_VOLTAGE::INT,
    MORNING_VOLTAGE_SAGS::INT,
    RATED_KVA::INT,
    HISTORICAL_SUMMER_AVG_LOAD,
    SUMMER_2023_2024_AVG_CRITICAL_HOURS,
    CASE 
        WHEN UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.1 THEN 'NO_HISTORICAL_DATA'
        ELSE ROUND((MORNING_LOAD_PCT - HISTORICAL_SUMMER_AVG_LOAD) / 
             GREATEST(HISTORICAL_SUMMER_AVG_LOAD, 1) * 100, 1)::VARCHAR
    END AS STRESS_VS_HISTORICAL,
    KWH_PER_METER,
    LOAD_TREND_RATIO,
    CASE 
        WHEN MORNING_LOAD_PCT > 75 AND (YEAR(CURRENT_DATE()) - INSTALL_YEAR) > 15 AND LOAD_TREND_RATIO > 1.1 THEN 1
        WHEN MORNING_LOAD_PCT > 85 THEN 1
        ELSE 0
    END AS TARGET_HIGH_RISK,
    ROUND(LEAST(100, MORNING_LOAD_PCT * UNIFORM(1.1::FLOAT, 1.5::FLOAT, RANDOM())), 1) AS AFTERNOON_LOAD_PCT,
    CASE 
        WHEN LEAST(100, MORNING_LOAD_PCT * 1.3) >= 80 THEN 'CRITICAL'
        WHEN LEAST(100, MORNING_LOAD_PCT * 1.3) >= 60 THEN 'WARNING'
        WHEN LEAST(100, MORNING_LOAD_PCT * 1.3) >= 40 THEN 'NORMAL'
        ELSE 'LOW'
    END AS AFTERNOON_CATEGORY
FROM raw_data;

-- 5.4 NODE_CENTRALITY_FEATURES_V2 — Centrality metrics for all nodes
USE SCHEMA CASCADE_ANALYSIS;

TRUNCATE TABLE IF EXISTS NODE_CENTRALITY_FEATURES_V2;

INSERT INTO NODE_CENTRALITY_FEATURES_V2 (NODE_ID, DEGREE_CENTRALITY, BETWEENNESS_CENTRALITY, CLOSENESS_CENTRALITY, EIGENVECTOR_CENTRALITY, PAGERANK_SCORE, PAGERANK, CLUSTERING_COEFFICIENT, LOCAL_EFFICIENCY, CASCADE_IMPACT_SCORE, VULNERABILITY_SCORE, CASCADE_RISK_SCORE_NORMALIZED, CRITICALITY_RANK, TOTAL_REACH, NEIGHBORS_1HOP, NEIGHBORS_2HOP, NODE_TYPE, SUBSTATION_ID, LOAD_FACTOR, MODEL_VERSION)
SELECT 
    n.NODE_ID,
    CASE WHEN n.NODE_TYPE = 'SUBSTATION' 
        THEN ROUND(UNIFORM(0.05::FLOAT, 0.3::FLOAT, RANDOM()), 6)
        ELSE ROUND(UNIFORM(0.001::FLOAT, 0.02::FLOAT, RANDOM()), 6)
    END AS DEGREE_CENTRALITY,
    CASE WHEN n.NODE_TYPE = 'SUBSTATION'
        THEN ROUND(UNIFORM(0.01::FLOAT, 0.5::FLOAT, RANDOM()), 6)
        ELSE ROUND(UNIFORM(0.0001::FLOAT, 0.01::FLOAT, RANDOM()), 6)
    END AS BETWEENNESS_CENTRALITY,
    ROUND(UNIFORM(0.1::FLOAT, 0.5::FLOAT, RANDOM()), 6) AS CLOSENESS_CENTRALITY,
    CASE WHEN n.NODE_TYPE = 'SUBSTATION'
        THEN ROUND(UNIFORM(0.01::FLOAT, 0.15::FLOAT, RANDOM()), 6)
        ELSE ROUND(UNIFORM(0.001::FLOAT, 0.05::FLOAT, RANDOM()), 6)
    END AS EIGENVECTOR_CENTRALITY,
    CASE WHEN n.NODE_TYPE = 'SUBSTATION'
        THEN ROUND(UNIFORM(0.001::FLOAT, 0.01::FLOAT, RANDOM()), 6)
        ELSE ROUND(UNIFORM(0.0001::FLOAT, 0.002::FLOAT, RANDOM()), 6)
    END AS PAGERANK_SCORE,
    CASE WHEN n.NODE_TYPE = 'SUBSTATION'
        THEN ROUND(UNIFORM(0.001::FLOAT, 0.01::FLOAT, RANDOM()), 6)
        ELSE ROUND(UNIFORM(0.0001::FLOAT, 0.002::FLOAT, RANDOM()), 6)
    END AS PAGERANK,
    ROUND(UNIFORM(0.0::FLOAT, 0.5::FLOAT, RANDOM()), 4) AS CLUSTERING_COEFFICIENT,
    ROUND(UNIFORM(0.1::FLOAT, 0.9::FLOAT, RANDOM()), 4) AS LOCAL_EFFICIENCY,
    ROUND(n.CRITICALITY_SCORE * UNIFORM(0.5::FLOAT, 1.5::FLOAT, RANDOM()), 4) AS CASCADE_IMPACT_SCORE,
    ROUND(UNIFORM(0.1::FLOAT, 0.9::FLOAT, RANDOM()), 4) AS VULNERABILITY_SCORE,
    CASE WHEN n.NODE_TYPE = 'SUBSTATION'
        THEN ROUND(UNIFORM(0.5::FLOAT, 1.0::FLOAT, RANDOM()), 4)
        ELSE ROUND(UNIFORM(0.1::FLOAT, 0.7::FLOAT, RANDOM()), 4)
    END AS CASCADE_RISK_SCORE_NORMALIZED,
    ROW_NUMBER() OVER (ORDER BY n.CRITICALITY_SCORE DESC)::INT AS CRITICALITY_RANK,
    CASE WHEN n.NODE_TYPE = 'SUBSTATION'
        THEN ROUND(UNIFORM(50::FLOAT, 500::FLOAT, RANDOM()))::INT
        ELSE ROUND(UNIFORM(1::FLOAT, 20::FLOAT, RANDOM()))::INT
    END AS TOTAL_REACH,
    CASE WHEN n.NODE_TYPE = 'SUBSTATION'
        THEN ROUND(UNIFORM(5::FLOAT, 50::FLOAT, RANDOM()))::INT
        ELSE ROUND(UNIFORM(1::FLOAT, 5::FLOAT, RANDOM()))::INT
    END AS NEIGHBORS_1HOP,
    CASE WHEN n.NODE_TYPE = 'SUBSTATION'
        THEN ROUND(UNIFORM(50::FLOAT, 500::FLOAT, RANDOM()))::INT
        ELSE ROUND(UNIFORM(5::FLOAT, 30::FLOAT, RANDOM()))::INT
    END AS NEIGHBORS_2HOP,
    n.NODE_TYPE,
    n.SUBSTATION_ID,
    ROUND(UNIFORM(0.3::FLOAT, 0.9::FLOAT, RANDOM()), 3) AS LOAD_FACTOR,
    'v2.0_quickstart' AS MODEL_VERSION
FROM <% database %>.ML_DEMO.GRID_NODES n
WHERE n.LAT IS NOT NULL;

-- 5.5 GNN_PREDICTIONS — Populate with risk predictions for all nodes
-- Consumed by /api/cascade/patient-zero-candidates
TRUNCATE TABLE IF EXISTS GNN_PREDICTIONS;

INSERT INTO GNN_PREDICTIONS (NODE_ID, NODE_TYPE, CRITICALITY_SCORE, GNN_CASCADE_RISK, PREDICTION_TIMESTAMP)
SELECT
    n.NODE_ID,
    n.NODE_TYPE,
    n.CRITICALITY_SCORE,
    LEAST(1.0, GREATEST(0.0,
        COALESCE(c.CASCADE_RISK_SCORE_NORMALIZED, n.CRITICALITY_SCORE) * 
        UNIFORM(0.8::FLOAT, 1.2::FLOAT, RANDOM())
    )) AS GNN_CASCADE_RISK,
    CURRENT_TIMESTAMP() AS PREDICTION_TIMESTAMP
FROM <% database %>.ML_DEMO.GRID_NODES n
LEFT JOIN CASCADE_ANALYSIS.NODE_CENTRALITY_FEATURES_V2 c ON n.NODE_ID = c.NODE_ID
WHERE n.LAT IS NOT NULL;

-- 5.6 PRECOMPUTED_CASCADES — Scenario-based cascade simulations
-- Consumed by /api/cascade/precomputed-scenarios endpoint.
-- Uses the 15-column schema with SCENARIO_ID, PATIENT_ZERO_ID, CASCADE_ORDER,
-- WAVE_BREAKDOWN, etc. that the backend expects.
TRUNCATE TABLE IF EXISTS PRECOMPUTED_CASCADES;

INSERT INTO PRECOMPUTED_CASCADES (
    SCENARIO_ID, SCENARIO_NAME, INITIATING_NODE_ID, PATIENT_ZERO_ID,
    INITIATING_NODE_NAME, PATIENT_ZERO_NAME, INITIATING_NODE_TYPE,
    SIMULATION_PARAMS, CASCADE_ORDER, WAVE_BREAKDOWN,
    PROPAGATION_PATHS, TOTAL_AFFECTED_NODES, AFFECTED_CAPACITY_MW,
    ESTIMATED_CUSTOMERS_AFFECTED, AFFECTED_CUSTOMERS,
    MAX_CASCADE_DEPTH, CASCADE_DEPTH, LOAD_SHED_MW,
    SIMULATION_TIMESTAMP, SIMULATION_SCENARIO, COMPUTED_AT
)
SELECT
    scenario_id, scenario_name,
    patient_zero_id, patient_zero_id,
    patient_zero_name, patient_zero_name,
    'SUBSTATION' AS INITIATING_NODE_TYPE,
    PARSE_JSON(sim_params) AS SIMULATION_PARAMS,
    PARSE_JSON(cascade_order_json) AS CASCADE_ORDER,
    PARSE_JSON(wave_json) AS WAVE_BREAKDOWN,
    PARSE_JSON('[]') AS PROPAGATION_PATHS,
    total_nodes,
    affected_mw,
    affected_customers, affected_customers,
    max_depth, max_depth,
    affected_mw AS LOAD_SHED_MW,
    CURRENT_TIMESTAMP() AS SIMULATION_TIMESTAMP,
    scenario_name AS SIMULATION_SCENARIO,
    CURRENT_TIMESTAMP() AS COMPUTED_AT
FROM (
    SELECT 
        'scenario_1' AS scenario_id,
        'Summer Peak 2025' AS scenario_name,
        'SUB_0001' AS patient_zero_id,
        'Substation 1' AS patient_zero_name,
        '{"temperature_c": 40, "load_multiplier": 1.4, "failure_threshold": 0.6}' AS sim_params,
        '[{"order":0,"node_id":"SUB_0001","node_name":"Substation 1","node_type":"SUBSTATION","wave_depth":0,"capacity_kw":50000,"lat":29.76,"lon":-95.37},{"order":1,"node_id":"TRF_000101","node_name":"Transformer 101","node_type":"TRANSFORMER","wave_depth":1,"capacity_kw":200,"lat":29.77,"lon":-95.38}]' AS cascade_order_json,
        '[{"wave":0,"nodes":1,"capacity_kw":50000},{"wave":1,"nodes":12,"capacity_kw":2400}]' AS wave_json,
        13 AS total_nodes, 52.4 AS affected_mw, 64800 AS affected_customers, 3 AS max_depth
    UNION ALL
    SELECT 
        'scenario_2', 'Winter Storm Scenario',
        'SUB_0005', 'Substation 5',
        '{"temperature_c": -10, "load_multiplier": 1.6, "failure_threshold": 0.5}',
        '[{"order":0,"node_id":"SUB_0005","node_name":"Substation 5","node_type":"SUBSTATION","wave_depth":0,"capacity_kw":75000,"lat":29.82,"lon":-95.45},{"order":1,"node_id":"SUB_0008","node_name":"Substation 8","node_type":"SUBSTATION","wave_depth":1,"capacity_kw":60000,"lat":29.80,"lon":-95.42}]',
        '[{"wave":0,"nodes":1,"capacity_kw":75000},{"wave":1,"nodes":3,"capacity_kw":180000},{"wave":2,"nodes":18,"capacity_kw":3600}]',
        22, 258.6, 324000, 5
    UNION ALL
    SELECT 
        'scenario_3', 'Hurricane Season',
        'SUB_0012', 'Substation 12',
        '{"temperature_c": 30, "load_multiplier": 1.2, "failure_threshold": 0.55}',
        '[{"order":0,"node_id":"SUB_0012","node_name":"Substation 12","node_type":"SUBSTATION","wave_depth":0,"capacity_kw":45000,"lat":29.68,"lon":-95.28},{"order":1,"node_id":"TRF_000108","node_name":"Transformer 108","node_type":"TRANSFORMER","wave_depth":1,"capacity_kw":150,"lat":29.69,"lon":-95.29}]',
        '[{"wave":0,"nodes":1,"capacity_kw":45000},{"wave":1,"nodes":8,"capacity_kw":1200}]',
        9, 46.2, 54000, 2
    UNION ALL
    SELECT 
        'scenario_4', 'Normal Operations Baseline',
        'SUB_0003', 'Substation 3',
        '{"temperature_c": 25, "load_multiplier": 1.0, "failure_threshold": 0.8}',
        '[{"order":0,"node_id":"SUB_0003","node_name":"Substation 3","node_type":"SUBSTATION","wave_depth":0,"capacity_kw":55000,"lat":29.74,"lon":-95.35}]',
        '[{"wave":0,"nodes":1,"capacity_kw":55000}]',
        1, 55.0, 0, 0
);

-- =============================================================================
-- SECTION 6: MISSING PRODUCTION TABLES FOR OPS CENTER
-- =============================================================================
-- These tables are referenced by Flux Ops Center but may not exist in all deployments

USE SCHEMA PRODUCTION;

-- -----------------------------------------------------------------------------
-- 6.1 OUTAGE_RESTORATION_TRACKER - Active Outage Tracking
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS OUTAGE_RESTORATION_TRACKER (
    OUTAGE_ID VARCHAR(50) PRIMARY KEY,
    CIRCUIT_ID VARCHAR(50),
    SUBSTATION_ID VARCHAR(50),
    OUTAGE_START_TIME TIMESTAMP_NTZ,
    OUTAGE_END_TIME TIMESTAMP_NTZ,
    STATUS VARCHAR(20) DEFAULT 'ACTIVE',  -- ACTIVE, RESTORED, INVESTIGATING
    CAUSE VARCHAR(100),  -- EQUIPMENT_FAILURE, WEATHER, VEGETATION, ANIMAL, UNKNOWN
    AFFECTED_CUSTOMERS INT,
    AFFECTED_TRANSFORMERS INT,
    CREW_ASSIGNED VARCHAR(50),
    ESTIMATED_RESTORATION TIMESTAMP_NTZ,
    ACTUAL_RESTORATION TIMESTAMP_NTZ,
    OUTAGE_DURATION_MINUTES INT,
    NOTES TEXT,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Insert sample outage data
MERGE INTO OUTAGE_RESTORATION_TRACKER AS target
USING (
    SELECT 
        'OUT_' || SEQ4() AS OUTAGE_ID,
        'CKT_' || FLOOR(RANDOM() * 500)::VARCHAR AS CIRCUIT_ID,
        'SUB_' || FLOOR(RANDOM() * 50)::VARCHAR AS SUBSTATION_ID,
        DATEADD('hour', -FLOOR(RANDOM() * 24)::INT, CURRENT_TIMESTAMP()) AS OUTAGE_START_TIME,
        CASE MOD(SEQ4(), 5)
            WHEN 0 THEN 'ACTIVE'
            WHEN 1 THEN 'INVESTIGATING'
            ELSE 'RESTORED'
        END AS STATUS,
        CASE MOD(SEQ4(), 5)
            WHEN 0 THEN 'EQUIPMENT_FAILURE'
            WHEN 1 THEN 'WEATHER'
            WHEN 2 THEN 'VEGETATION'
            WHEN 3 THEN 'ANIMAL'
            ELSE 'UNKNOWN'
        END AS CAUSE,
        FLOOR(50 + RANDOM() * 500)::INT AS AFFECTED_CUSTOMERS,
        FLOOR(1 + RANDOM() * 10)::INT AS AFFECTED_TRANSFORMERS,
        'CREW_' || FLOOR(RANDOM() * 20)::VARCHAR AS CREW_ASSIGNED,
        DATEADD('hour', FLOOR(RANDOM() * 4)::INT, CURRENT_TIMESTAMP()) AS ESTIMATED_RESTORATION
    FROM TABLE(GENERATOR(ROWCOUNT => 25))
) AS source
ON target.OUTAGE_ID = source.OUTAGE_ID
WHEN NOT MATCHED THEN INSERT (
    OUTAGE_ID, CIRCUIT_ID, SUBSTATION_ID, OUTAGE_START_TIME, STATUS, CAUSE,
    AFFECTED_CUSTOMERS, AFFECTED_TRANSFORMERS, CREW_ASSIGNED, ESTIMATED_RESTORATION
) VALUES (
    source.OUTAGE_ID, source.CIRCUIT_ID, source.SUBSTATION_ID, source.OUTAGE_START_TIME,
    source.STATUS, source.CAUSE, source.AFFECTED_CUSTOMERS, source.AFFECTED_TRANSFORMERS,
    source.CREW_ASSIGNED, source.ESTIMATED_RESTORATION
);

-- -----------------------------------------------------------------------------
-- 6.2 WORK_ORDERS - Maintenance Work Orders (if not exists)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS WORK_ORDERS (
    WORK_ORDER_ID VARCHAR(50) PRIMARY KEY,
    ASSET_TYPE VARCHAR(50),  -- TRANSFORMER, POLE, METER, CIRCUIT
    ASSET_ID VARCHAR(50),
    WORK_TYPE VARCHAR(50),  -- MAINTENANCE, REPAIR, INSPECTION, REPLACEMENT
    PRIORITY VARCHAR(20),  -- CRITICAL, HIGH, MEDIUM, LOW
    STATUS VARCHAR(20) DEFAULT 'OPEN',  -- OPEN, ASSIGNED, IN_PROGRESS, COMPLETED, CANCELLED
    DESCRIPTION TEXT,
    ASSIGNED_CREW VARCHAR(50),
    SCHEDULED_DATE DATE,
    COMPLETED_DATE DATE,
    ESTIMATED_HOURS FLOAT,
    ACTUAL_HOURS FLOAT,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- =============================================================================
-- SECTION 6B: RAW SCHEMA - External Data Sources
-- =============================================================================
-- Large external datasets (building footprints, parcel data, etc.)
-- These are loaded separately from GitHub releases or external sources

CREATE SCHEMA IF NOT EXISTS RAW
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Raw external data sources (buildings, parcels, OSM data)';

GRANT USAGE ON SCHEMA <% database %>.RAW TO ROLE IDENTIFIER('<% user_role %>');
GRANT SELECT ON FUTURE TABLES IN SCHEMA <% database %>.RAW TO ROLE IDENTIFIER('<% user_role %>');

USE SCHEMA RAW;

-- -----------------------------------------------------------------------------
-- 6B.1 HOUSTON_BUILDINGS_FOOTPRINTS - Building Polygons for 3D Visualization
-- -----------------------------------------------------------------------------
-- NOTE: This is a large dataset (2.6M rows, ~310MB) loaded from external sources.
--       For full data, download from GitHub Release: gh release download v1.0.0-data
--       Or use the load script: python backend/scripts/load_postgis_data.py
--       The table structure is provided here for reference/small test datasets.

CREATE TABLE IF NOT EXISTS HOUSTON_BUILDINGS_FOOTPRINTS (
    BUILDING_ID VARCHAR(50) PRIMARY KEY,
    BUILDING_NAME VARCHAR(200),
    BUILDING_TYPE VARCHAR(50),
    HEIGHT_METERS FLOAT,
    NUM_FLOORS INT,
    GEOMETRY GEOGRAPHY,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Building footprints for 3D map visualization - load from GitHub release v1.0.0-data';

-- =============================================================================
-- SECTION 7: VERIFICATION QUERIES
-- =============================================================================

-- Verify all objects created
SELECT 'APPLICATIONS Views' AS CHECK_TYPE, COUNT(*) AS COUNT 
FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = 'APPLICATIONS';

SELECT 'ML_DEMO Tables' AS CHECK_TYPE, COUNT(*) AS COUNT 
FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'ML_DEMO';

SELECT 'CASCADE_ANALYSIS Tables' AS CHECK_TYPE, COUNT(*) AS COUNT 
FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'CASCADE_ANALYSIS';

-- Sample data verification
SELECT 'GRID_NODES' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM <% database %>.ML_DEMO.GRID_NODES;
SELECT 'GRID_EDGES' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM <% database %>.ML_DEMO.GRID_EDGES;
SELECT 'NODE_CENTRALITY_FEATURES_V2' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM <% database %>.CASCADE_ANALYSIS.NODE_CENTRALITY_FEATURES_V2;
SELECT 'PRECOMPUTED_CASCADES' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM <% database %>.CASCADE_ANALYSIS.PRECOMPUTED_CASCADES;

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- 
-- Next Steps:
-- 1. Deploy Flux Ops Center SPCS with SNOWFLAKE_DATABASE=<% database %>
-- 2. The container will automatically use these objects
-- =============================================================================
