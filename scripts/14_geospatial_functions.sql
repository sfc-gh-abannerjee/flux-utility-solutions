-- =============================================================================
-- 14_geospatial_functions.sql
-- Flux Utility Solutions - Geospatial Functions and H3 Integration
-- =============================================================================
-- Purpose: Create geospatial functions for grid topology analysis
-- Dependencies: 03_substations_transformers.sql, 04_meters_infrastructure.sql
-- Jinja2 Variables:
--   <% database %>  - Target database name
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE SCHEMA PRODUCTION;

-- -----------------------------------------------------------------------------
-- 1. H3 INDEX COLUMNS ON INFRASTRUCTURE TABLES
-- -----------------------------------------------------------------------------
-- Add H3 indexes for efficient geospatial queries

-- Add H3 column to substations
ALTER TABLE SUBSTATIONS ADD COLUMN IF NOT EXISTS 
    H3_INDEX_RES9 VARCHAR(20);

UPDATE SUBSTATIONS 
SET H3_INDEX_RES9 = H3_LATLNG_TO_CELL_STRING(LATITUDE, LONGITUDE, 9)
WHERE H3_INDEX_RES9 IS NULL AND LATITUDE IS NOT NULL;

-- Add H3 column to transformers
ALTER TABLE TRANSFORMER_METADATA ADD COLUMN IF NOT EXISTS 
    H3_INDEX_RES9 VARCHAR(20);

UPDATE TRANSFORMER_METADATA 
SET H3_INDEX_RES9 = H3_LATLNG_TO_CELL_STRING(LATITUDE, LONGITUDE, 9)
WHERE H3_INDEX_RES9 IS NULL AND LATITUDE IS NOT NULL;

-- Add H3 column to meters
ALTER TABLE METER_INFRASTRUCTURE ADD COLUMN IF NOT EXISTS 
    H3_INDEX_RES9 VARCHAR(20);

UPDATE METER_INFRASTRUCTURE 
SET H3_INDEX_RES9 = H3_LATLNG_TO_CELL_STRING(
    CAST(SPLIT_PART(LOCATION, ',', 1) AS FLOAT),
    CAST(SPLIT_PART(LOCATION, ',', 2) AS FLOAT),
    9
)
WHERE H3_INDEX_RES9 IS NULL AND LOCATION IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 2. GEOSPATIAL ANALYSIS FUNCTIONS
-- -----------------------------------------------------------------------------

-- Function: Find nearby transformers within radius
CREATE OR REPLACE FUNCTION FIND_NEARBY_TRANSFORMERS(
    P_LAT FLOAT,
    P_LON FLOAT,
    P_RADIUS_KM FLOAT DEFAULT 5.0
)
RETURNS TABLE (
    TRANSFORMER_ID VARCHAR,
    DISTANCE_KM FLOAT,
    RATED_KVA NUMBER,
    LOAD_UTILIZATION_PCT FLOAT,
    HEALTH_SCORE NUMBER
)
LANGUAGE SQL
COMMENT = 'Find transformers within specified radius of a point'
AS
$$
    SELECT 
        TRANSFORMER_ID,
        HAVERSINE(P_LAT, P_LON, LATITUDE, LONGITUDE) AS DISTANCE_KM,
        RATED_KVA,
        LOAD_UTILIZATION_PCT,
        HEALTH_SCORE
    FROM TRANSFORMER_METADATA
    WHERE HAVERSINE(P_LAT, P_LON, LATITUDE, LONGITUDE) <= P_RADIUS_KM
    ORDER BY DISTANCE_KM
$$;

-- Function: Calculate service territory coverage
CREATE OR REPLACE FUNCTION SERVICE_TERRITORY_COVERAGE(
    P_H3_RESOLUTION NUMBER DEFAULT 7
)
RETURNS TABLE (
    H3_INDEX VARCHAR,
    SUBSTATION_COUNT NUMBER,
    TRANSFORMER_COUNT NUMBER,
    METER_COUNT NUMBER,
    TOTAL_CAPACITY_KVA NUMBER
)
LANGUAGE SQL
COMMENT = 'Calculate infrastructure coverage by H3 hexagon'
AS
$$
    WITH hex_coverage AS (
        SELECT 
            H3_LATLNG_TO_CELL_STRING(LATITUDE, LONGITUDE, P_H3_RESOLUTION) AS H3_INDEX,
            COUNT(DISTINCT s.SUBSTATION_ID) AS SUBSTATION_COUNT,
            0 AS TRANSFORMER_COUNT,
            0 AS METER_COUNT,
            SUM(s.TOTAL_CAPACITY_MVA * 1000) AS TOTAL_CAPACITY_KVA
        FROM SUBSTATIONS s
        GROUP BY 1
        
        UNION ALL
        
        SELECT 
            H3_LATLNG_TO_CELL_STRING(LATITUDE, LONGITUDE, P_H3_RESOLUTION) AS H3_INDEX,
            0 AS SUBSTATION_COUNT,
            COUNT(DISTINCT t.TRANSFORMER_ID) AS TRANSFORMER_COUNT,
            0 AS METER_COUNT,
            SUM(t.RATED_KVA) AS TOTAL_CAPACITY_KVA
        FROM TRANSFORMER_METADATA t
        GROUP BY 1
    )
    SELECT 
        H3_INDEX,
        SUM(SUBSTATION_COUNT) AS SUBSTATION_COUNT,
        SUM(TRANSFORMER_COUNT) AS TRANSFORMER_COUNT,
        SUM(METER_COUNT) AS METER_COUNT,
        SUM(TOTAL_CAPACITY_KVA) AS TOTAL_CAPACITY_KVA
    FROM hex_coverage
    GROUP BY H3_INDEX
$$;

-- Function: Identify coverage gaps
CREATE OR REPLACE FUNCTION IDENTIFY_COVERAGE_GAPS(
    P_MIN_METERS_PER_HEX NUMBER DEFAULT 10
)
RETURNS TABLE (
    H3_INDEX VARCHAR,
    CENTER_LAT FLOAT,
    CENTER_LON FLOAT,
    METER_COUNT NUMBER,
    NEAREST_SUBSTATION_KM FLOAT,
    GAP_TYPE VARCHAR
)
LANGUAGE SQL
COMMENT = 'Identify areas with insufficient grid coverage'
AS
$$
    WITH meter_hexes AS (
        SELECT 
            H3_INDEX_RES9 AS H3_INDEX,
            COUNT(*) AS METER_COUNT
        FROM METER_INFRASTRUCTURE
        WHERE H3_INDEX_RES9 IS NOT NULL
        GROUP BY 1
    ),
    hex_centers AS (
        SELECT 
            H3_INDEX,
            METER_COUNT,
            H3_CELL_TO_LAT(H3_INDEX) AS CENTER_LAT,
            H3_CELL_TO_LNG(H3_INDEX) AS CENTER_LON
        FROM meter_hexes
        WHERE METER_COUNT < P_MIN_METERS_PER_HEX
    )
    SELECT 
        h.H3_INDEX,
        h.CENTER_LAT,
        h.CENTER_LON,
        h.METER_COUNT,
        MIN(HAVERSINE(h.CENTER_LAT, h.CENTER_LON, s.LATITUDE, s.LONGITUDE)) AS NEAREST_SUBSTATION_KM,
        CASE 
            WHEN MIN(HAVERSINE(h.CENTER_LAT, h.CENTER_LON, s.LATITUDE, s.LONGITUDE)) > 10 
                THEN 'CRITICAL_GAP'
            WHEN MIN(HAVERSINE(h.CENTER_LAT, h.CENTER_LON, s.LATITUDE, s.LONGITUDE)) > 5 
                THEN 'MODERATE_GAP'
            ELSE 'MINOR_GAP'
        END AS GAP_TYPE
    FROM hex_centers h
    CROSS JOIN SUBSTATIONS s
    GROUP BY h.H3_INDEX, h.CENTER_LAT, h.CENTER_LON, h.METER_COUNT
$$;

-- -----------------------------------------------------------------------------
-- 3. CASCADE FAILURE ANALYSIS FUNCTIONS
-- -----------------------------------------------------------------------------

-- Function: Find downstream assets from a failure point
CREATE OR REPLACE FUNCTION CASCADE_DOWNSTREAM_ASSETS(
    P_ASSET_ID VARCHAR,
    P_ASSET_TYPE VARCHAR DEFAULT 'TRANSFORMER'
)
RETURNS TABLE (
    DOWNSTREAM_ASSET_ID VARCHAR,
    ASSET_TYPE VARCHAR,
    HOPS_FROM_SOURCE NUMBER,
    AFFECTED_CUSTOMERS NUMBER
)
LANGUAGE SQL
COMMENT = 'Find all assets downstream from a potential failure point'
AS
$$
    WITH RECURSIVE cascade_path AS (
        -- Base case: starting asset
        SELECT 
            P_ASSET_ID AS ASSET_ID,
            P_ASSET_TYPE AS ASSET_TYPE,
            0 AS HOPS
        
        UNION ALL
        
        -- Recursive case: find connected assets
        SELECT 
            CASE 
                WHEN cp.ASSET_TYPE = 'SUBSTATION' THEN t.TRANSFORMER_ID
                WHEN cp.ASSET_TYPE = 'TRANSFORMER' THEN m.METER_ID
                ELSE NULL
            END AS ASSET_ID,
            CASE 
                WHEN cp.ASSET_TYPE = 'SUBSTATION' THEN 'TRANSFORMER'
                WHEN cp.ASSET_TYPE = 'TRANSFORMER' THEN 'METER'
                ELSE NULL
            END AS ASSET_TYPE,
            cp.HOPS + 1 AS HOPS
        FROM cascade_path cp
        LEFT JOIN TRANSFORMER_METADATA t ON cp.ASSET_TYPE = 'SUBSTATION' 
            AND t.SUBSTATION_ID = cp.ASSET_ID
        LEFT JOIN METER_INFRASTRUCTURE m ON cp.ASSET_TYPE = 'TRANSFORMER' 
            AND m.TRANSFORMER_ID = cp.ASSET_ID
        WHERE cp.HOPS < 3  -- Limit recursion depth
    )
    SELECT 
        cp.ASSET_ID AS DOWNSTREAM_ASSET_ID,
        cp.ASSET_TYPE,
        cp.HOPS AS HOPS_FROM_SOURCE,
        CASE 
            WHEN cp.ASSET_TYPE = 'METER' THEN 1
            WHEN cp.ASSET_TYPE = 'TRANSFORMER' THEN 
                (SELECT COUNT(*) FROM METER_INFRASTRUCTURE WHERE TRANSFORMER_ID = cp.ASSET_ID)
            ELSE 0
        END AS AFFECTED_CUSTOMERS
    FROM cascade_path cp
    WHERE cp.ASSET_ID IS NOT NULL
$$;

-- -----------------------------------------------------------------------------
-- 4. GRID TOPOLOGY VIEW
-- -----------------------------------------------------------------------------

CREATE OR ALTER VIEW APPLICATIONS.GRID_TOPOLOGY_GEO AS
SELECT
    'SUBSTATION' AS ASSET_TYPE,
    SUBSTATION_ID AS ASSET_ID,
    SUBSTATION_NAME AS ASSET_NAME,
    LATITUDE,
    LONGITUDE,
    H3_INDEX_RES9,
    TO_GEOGRAPHY(ST_MAKEPOINT(LONGITUDE, LATITUDE)) AS GEO_POINT,
    TOTAL_CAPACITY_MVA * 1000 AS CAPACITY_KVA,
    NULL AS PARENT_ASSET_ID
FROM PRODUCTION.SUBSTATIONS
WHERE LATITUDE IS NOT NULL

UNION ALL

SELECT
    'TRANSFORMER' AS ASSET_TYPE,
    TRANSFORMER_ID AS ASSET_ID,
    TRANSFORMER_ID AS ASSET_NAME,
    LATITUDE,
    LONGITUDE,
    H3_INDEX_RES9,
    TO_GEOGRAPHY(ST_MAKEPOINT(LONGITUDE, LATITUDE)) AS GEO_POINT,
    RATED_KVA AS CAPACITY_KVA,
    SUBSTATION_ID AS PARENT_ASSET_ID
FROM PRODUCTION.TRANSFORMER_METADATA
WHERE LATITUDE IS NOT NULL;

-- Grant access
GRANT SELECT ON VIEW APPLICATIONS.GRID_TOPOLOGY_GEO TO ROLE IDENTIFIER('<% user_role %>');

-- -----------------------------------------------------------------------------
-- 5. VERIFICATION
-- -----------------------------------------------------------------------------

-- Verify H3 indexes
SELECT 'SUBSTATIONS' AS TABLE_NAME, COUNT(*) AS WITH_H3, 
       (SELECT COUNT(*) FROM SUBSTATIONS) AS TOTAL
FROM SUBSTATIONS WHERE H3_INDEX_RES9 IS NOT NULL;

SELECT 'TRANSFORMERS' AS TABLE_NAME, COUNT(*) AS WITH_H3,
       (SELECT COUNT(*) FROM TRANSFORMER_METADATA) AS TOTAL
FROM TRANSFORMER_METADATA WHERE H3_INDEX_RES9 IS NOT NULL;

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 15_marketplace_listings.sql for data marketplace setup
-- =============================================================================

-- =============================================================================
-- H3 RING-EXPANSION PROXIMITY  (added 2026-07-29)
-- =============================================================================
-- Why a RING and not a plain cell-equality join:
--   An equality join on H3_INDEX_RES9 alone finds only assets in the SAME cell.
--   Res-9 cells have ~174 m edges, so an asset 200 m away sitting just across a
--   cell boundary would be silently EXCLUDED. That is a correctness bug, not a
--   performance trade-off. H3_GRID_DISK expands to a k-ring of candidate cells
--   first, then an exact HAVERSINE filter trims to the true radius.
--
-- Why this is the scale pattern:
--   Candidates arrive via an equality join against a small cell set (k=2 is 19
--   cells) instead of an O(n^2) distance cross join over every asset. This is
--   what keeps proximity queries viable at utility volumes.
--
-- Ring sizing:  k = ceil(radius_m / 174) + 1
--   Verified against a naive full-scan on se_demo: 500 m -> 15 vs 15 matches,
--   2000 m -> 165 vs 165 matches, identical maxima. No missed assets.
--
-- Requires H3_INDEX_RES9 to be populated (see the H3 section above and
-- scripts/31_regenerate_coherent_topology.sql).

CREATE OR REPLACE FUNCTION <% database %>.APPLICATIONS.F_METERS_NEAR(
    P_LAT FLOAT, P_LON FLOAT, P_RADIUS_M FLOAT
)
RETURNS TABLE (METER_ID VARCHAR, TRANSFORMER_ID VARCHAR, CIRCUIT_ID VARCHAR,
               LATITUDE FLOAT, LONGITUDE FLOAT, DISTANCE_M FLOAT)
COMMENT = 'Meters within P_RADIUS_M metres of a point, via H3 ring-expansion candidate generation plus an exact HAVERSINE filter. Ring size is derived from the radius because a bare cell-equality join would miss neighbours across a cell boundary.'
AS
$$
WITH origin AS (
    SELECT H3_LATLNG_TO_CELL_STRING(P_LAT, P_LON, 9) AS CELL,
           GREATEST(1, CEIL(P_RADIUS_M / 174.0) + 1)::INT AS K
),
candidate_cells AS (
    SELECT f.VALUE::VARCHAR AS CELL
    FROM origin o, LATERAL FLATTEN(input => H3_GRID_DISK(o.CELL, o.K)) f
)
SELECT m.METER_ID, m.TRANSFORMER_ID, m.CIRCUIT_ID, m.LATITUDE, m.LONGITUDE,
       ROUND(HAVERSINE(P_LAT, P_LON, m.LATITUDE, m.LONGITUDE) * 1000, 1) AS DISTANCE_M
FROM <% database %>.PRODUCTION.METER_INFRASTRUCTURE m
JOIN candidate_cells c ON m.H3_INDEX_RES9 = c.CELL
WHERE HAVERSINE(P_LAT, P_LON, m.LATITUDE, m.LONGITUDE) * 1000 <= P_RADIUS_M
$$;

-- Correctness harness: the H3 path must return EXACTLY what a naive scan returns.
-- Substitute a real anchor; a MISMATCH means the ring sizing regressed.
--   WITH h3 AS (SELECT COUNT(*) n FROM TABLE(F_METERS_NEAR(29.751809, -95.125192, 2000::FLOAT))),
--        naive AS (SELECT COUNT(*) n FROM PRODUCTION.METER_INFRASTRUCTURE
--                   WHERE HAVERSINE(29.751809,-95.125192,LATITUDE,LONGITUDE)*1000 <= 2000)
--   SELECT CASE WHEN h3.n = naive.n THEN 'PASS' ELSE 'FAIL' END FROM h3, naive;
