-- ============================================================================
-- 32_topology_invariants.sql
-- ============================================================================
-- Enforced invariants for the grid topology.
--
-- WHY THIS EXISTS
--   Three separate defects survived for months in this demo, and every one of
--   them would have been caught on day one by an assertion in this file:
--
--     1. Coordinates of ~4.6e17 from bare RANDOM() arithmetic. A coordinate
--        range assertion catches it instantly.
--     2. 100 of 101 transformer substation keys orphaned across four ID key
--        spaces. An orphan assertion catches it instantly.
--     3. Two independent BROKEN COLUMN CONTRACTS -- a backend endpoint and the
--        Postgres sync each SELECTing a fixed column list from a view that did
--        not have those columns, returning HTTP 500 / silently never syncing.
--        A column-contract assertion catches it instantly.
--
--   scripts/99_validate_deployment.sql previously asserted ROW COUNTS ONLY.
--   Row counts passing while the story is silently broken is exactly the
--   failure mode this file closes.
--
-- HOW TO RUN
--   snow sql -f scripts/32_topology_invariants.sql -D "database=FLUX_DB" -D "schema=PRODUCTION"
--   Every check returns a row with STATUS = 'PASS' or 'FAIL'. Any FAIL is a
--   release blocker. Intended to be run by CI after any topology change.
-- ============================================================================

USE DATABASE IDENTIFIER('<% database %>');

-- ---------------------------------------------------------------------------
-- SECTION 1 -- Coordinate validity
-- Houston service territory: lat 28.0-31.0, lon -97.0..-93.5
-- ---------------------------------------------------------------------------
WITH checks AS (
    SELECT 'SUBSTATIONS' AS OBJ, COUNT(*) AS TOTAL,
           SUM(CASE WHEN LATITUDE IS NULL OR LONGITUDE IS NULL THEN 1 ELSE 0 END)
         + SUM(CASE WHEN LATITUDE NOT BETWEEN 28 AND 31
                      OR LONGITUDE NOT BETWEEN -97 AND -93.5 THEN 1 ELSE 0 END) AS BAD
      FROM PRODUCTION.SUBSTATIONS
    UNION ALL
    SELECT 'CIRCUIT_METADATA', COUNT(*),
           SUM(CASE WHEN REPRESENTATIVE_LAT IS NULL OR REPRESENTATIVE_LON IS NULL THEN 1 ELSE 0 END)
         + SUM(CASE WHEN REPRESENTATIVE_LAT NOT BETWEEN 28 AND 31
                      OR REPRESENTATIVE_LON NOT BETWEEN -97 AND -93.5 THEN 1 ELSE 0 END)
      FROM PRODUCTION.CIRCUIT_METADATA
    UNION ALL
    SELECT 'TRANSFORMER_METADATA', COUNT(*),
           SUM(CASE WHEN LATITUDE IS NULL OR LONGITUDE IS NULL THEN 1 ELSE 0 END)
         + SUM(CASE WHEN LATITUDE NOT BETWEEN 28 AND 31
                      OR LONGITUDE NOT BETWEEN -97 AND -93.5 THEN 1 ELSE 0 END)
      FROM PRODUCTION.TRANSFORMER_METADATA
    UNION ALL
    SELECT 'GRID_POLES_INFRASTRUCTURE', COUNT(*),
           SUM(CASE WHEN LATITUDE IS NULL OR LONGITUDE IS NULL THEN 1 ELSE 0 END)
         + SUM(CASE WHEN LATITUDE NOT BETWEEN 28 AND 31
                      OR LONGITUDE NOT BETWEEN -97 AND -93.5 THEN 1 ELSE 0 END)
      FROM PRODUCTION.GRID_POLES_INFRASTRUCTURE
    UNION ALL
    SELECT 'METER_INFRASTRUCTURE', COUNT(*),
           SUM(CASE WHEN LATITUDE IS NULL OR LONGITUDE IS NULL THEN 1 ELSE 0 END)
         + SUM(CASE WHEN LATITUDE NOT BETWEEN 28 AND 31
                      OR LONGITUDE NOT BETWEEN -97 AND -93.5 THEN 1 ELSE 0 END)
      FROM PRODUCTION.METER_INFRASTRUCTURE
)
SELECT 'V1 COORDINATE VALIDITY' AS CHECK_NAME, OBJ AS DETAIL,
       TOTAL, BAD AS VIOLATIONS,
       CASE WHEN BAD = 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM checks ORDER BY OBJ;

-- ---------------------------------------------------------------------------
-- SECTION 2 -- Referential integrity: zero orphans, both directions
-- ---------------------------------------------------------------------------
WITH orph AS (
    SELECT 'circuit -> substation' AS REL, COUNT(*) AS ORPHANS
      FROM PRODUCTION.CIRCUIT_METADATA c
      LEFT JOIN PRODUCTION.SUBSTATIONS s ON c.SUBSTATION_ID = s.SUBSTATION_ID
     WHERE s.SUBSTATION_ID IS NULL
    UNION ALL
    SELECT 'transformer -> circuit', COUNT(*)
      FROM PRODUCTION.TRANSFORMER_METADATA t
      LEFT JOIN PRODUCTION.CIRCUIT_METADATA c ON t.CIRCUIT_ID = c.CIRCUIT_ID
     WHERE c.CIRCUIT_ID IS NULL
    UNION ALL
    SELECT 'transformer -> substation', COUNT(*)
      FROM PRODUCTION.TRANSFORMER_METADATA t
      LEFT JOIN PRODUCTION.SUBSTATIONS s ON t.SUBSTATION_ID = s.SUBSTATION_ID
     WHERE s.SUBSTATION_ID IS NULL
    UNION ALL
    SELECT 'pole -> transformer', COUNT(*)
      FROM PRODUCTION.GRID_POLES_INFRASTRUCTURE p
      LEFT JOIN PRODUCTION.TRANSFORMER_METADATA t ON p.TRANSFORMER_ID = t.TRANSFORMER_ID
     WHERE t.TRANSFORMER_ID IS NULL
    UNION ALL
    SELECT 'meter -> pole', COUNT(*)
      FROM PRODUCTION.METER_INFRASTRUCTURE m
      LEFT JOIN PRODUCTION.GRID_POLES_INFRASTRUCTURE p ON m.POLE_ID = p.POLE_ID
     WHERE p.POLE_ID IS NULL
    UNION ALL
    SELECT 'meter -> transformer', COUNT(*)
      FROM PRODUCTION.METER_INFRASTRUCTURE m
      LEFT JOIN PRODUCTION.TRANSFORMER_METADATA t ON m.TRANSFORMER_ID = t.TRANSFORMER_ID
     WHERE t.TRANSFORMER_ID IS NULL
    UNION ALL
    SELECT 'outage -> substation', COUNT(*)
      FROM PRODUCTION.OUTAGE_RESTORATION_TRACKER o
      LEFT JOIN PRODUCTION.SUBSTATIONS s ON o.SUBSTATION_ID = s.SUBSTATION_ID
     WHERE o.SUBSTATION_ID IS NOT NULL AND s.SUBSTATION_ID IS NULL
    UNION ALL
    SELECT 'outage -> circuit', COUNT(*)
      FROM PRODUCTION.OUTAGE_RESTORATION_TRACKER o
      LEFT JOIN PRODUCTION.CIRCUIT_METADATA c ON o.CIRCUIT_ID = c.CIRCUIT_ID
     WHERE o.CIRCUIT_ID IS NOT NULL AND c.CIRCUIT_ID IS NULL
    UNION ALL
    SELECT 'outage -> transformer', COUNT(*)
      FROM PRODUCTION.OUTAGE_RESTORATION_TRACKER o
      LEFT JOIN PRODUCTION.TRANSFORMER_METADATA t ON o.TRANSFORMER_ID = t.TRANSFORMER_ID
     WHERE o.TRANSFORMER_ID IS NOT NULL AND t.TRANSFORMER_ID IS NULL
)
SELECT 'V2 REFERENTIAL INTEGRITY' AS CHECK_NAME, REL AS DETAIL,
       NULL AS TOTAL, ORPHANS AS VIOLATIONS,
       CASE WHEN ORPHANS = 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM orph ORDER BY REL;

-- ---------------------------------------------------------------------------
-- SECTION 3 -- Spatial invariants
-- Thresholds from GEOGRAPHIC_REALISM_AUDIT_JAN5_2026.md, which measured this
-- dataset while it was still coherent. These are REGRESSION GATES: with bounded
-- disc placement they are satisfied by construction, so a failure means the
-- generator or a view changed, not that a target was missed.
-- ---------------------------------------------------------------------------
WITH mp AS (
    SELECT HAVERSINE(m.LATITUDE, m.LONGITUDE, p.LATITUDE, p.LONGITUDE) AS D
      FROM PRODUCTION.METER_INFRASTRUCTURE m
      JOIN PRODUCTION.GRID_POLES_INFRASTRUCTURE p ON m.POLE_ID = p.POLE_ID
), pt AS (
    SELECT HAVERSINE(p.LATITUDE, p.LONGITUDE, t.LATITUDE, t.LONGITUDE) AS D
      FROM PRODUCTION.GRID_POLES_INFRASTRUCTURE p
      JOIN PRODUCTION.TRANSFORMER_METADATA t ON p.TRANSFORMER_ID = t.TRANSFORMER_ID
), ts AS (
    SELECT HAVERSINE(t.LATITUDE, t.LONGITUDE, s.LATITUDE, s.LONGITUDE) AS D
      FROM PRODUCTION.TRANSFORMER_METADATA t
      JOIN PRODUCTION.SUBSTATIONS s ON t.SUBSTATION_ID = s.SUBSTATION_ID
), span AS (
    SELECT HAVERSINE(MIN(LATITUDE), MIN(LONGITUDE), MAX(LATITUDE), MAX(LONGITUDE)) AS D
      FROM PRODUCTION.TRANSFORMER_METADATA GROUP BY CIRCUIT_ID
), gates AS (
    SELECT 'meter -> pole within 1 km' AS GATE, 97.5 AS REQUIRED_PCT,
           ROUND(100.0 * SUM(CASE WHEN D <= 1 THEN 1 ELSE 0 END) / COUNT(*), 3) AS ACTUAL_PCT,
           ROUND(AVG(D) * 1000, 1) AS MEAN_M FROM mp
    UNION ALL
    SELECT 'pole -> transformer within 500 m', 99.0,
           ROUND(100.0 * SUM(CASE WHEN D <= 0.5 THEN 1 ELSE 0 END) / COUNT(*), 3),
           ROUND(AVG(D) * 1000, 1) FROM pt
    UNION ALL
    SELECT 'transformer -> substation within 15 km', 99.5,
           ROUND(100.0 * SUM(CASE WHEN D <= 15 THEN 1 ELSE 0 END) / COUNT(*), 3),
           ROUND(AVG(D) * 1000, 1) FROM ts
    UNION ALL
    SELECT 'circuit span under 10 km', 90.0,
           ROUND(100.0 * SUM(CASE WHEN D <= 10 THEN 1 ELSE 0 END) / COUNT(*), 3),
           ROUND(AVG(D) * 1000, 1) FROM span
)
SELECT 'V3 SPATIAL INVARIANTS' AS CHECK_NAME, GATE AS DETAIL,
       REQUIRED_PCT, ACTUAL_PCT, MEAN_M,
       CASE WHEN ACTUAL_PCT >= REQUIRED_PCT THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM gates ORDER BY GATE;

-- ---------------------------------------------------------------------------
-- SECTION 4 -- No absurd edges in any topology view
-- Catches the RANDOM()-as-float class directly: a real distribution edge is
-- never 100 km, and NaN is never acceptable.
-- ---------------------------------------------------------------------------
WITH e AS (
    SELECT FROM_ASSET_TYPE || ' -> ' || TO_ASSET_TYPE AS EDGE,
           HAVERSINE(FROM_LATITUDE, FROM_LONGITUDE, TO_LATITUDE, TO_LONGITUDE) AS D,
           TO_LATITUDE, TO_LONGITUDE
      FROM APPLICATIONS.FLUX_OPS_CENTER_TOPOLOGY
)
SELECT 'V4 NO ABSURD EDGES' AS CHECK_NAME, EDGE AS DETAIL,
       COUNT(*) AS TOTAL,
       SUM(CASE WHEN D > 100 OR D IS NULL
                     OR TO_LATITUDE  NOT BETWEEN 28 AND 31
                     OR TO_LONGITUDE NOT BETWEEN -97 AND -93.5
                THEN 1 ELSE 0 END) AS VIOLATIONS,
       CASE WHEN SUM(CASE WHEN D > 100 OR D IS NULL
                               OR TO_LATITUDE  NOT BETWEEN 28 AND 31
                               OR TO_LONGITUDE NOT BETWEEN -97 AND -93.5
                          THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM e GROUP BY EDGE ORDER BY EDGE;

-- ---------------------------------------------------------------------------
-- SECTION 5 -- COLUMN CONTRACTS  (the check that would have caught two bugs)
--
-- Any view a backend endpoint or sync job SELECTs by an explicit column list is
-- a contract. If the view stops exposing a column, the consumer breaks --
-- HTTP 500 for an endpoint, or a silently-never-refreshed cache for a sync job.
-- Add a row here whenever a consumer hardcodes a column list.
-- ---------------------------------------------------------------------------
WITH contracts AS (
    SELECT 'FLUX_OPS_CENTER_TOPOLOGY_FEEDERS' AS VIEW_NAME,
           'backend/server_fastapi.py /api/topology/feeders' AS CONSUMER,
           ARRAY_CONSTRUCT('SUBSTATION_ID','TRANSFORMER_ID','CONNECTION_TYPE',
                           'FROM_LATITUDE','FROM_LONGITUDE','TO_LATITUDE','TO_LONGITUDE',
                           'LOAD_UTILIZATION_PCT','CIRCUIT_ID','RATED_KVA',
                           'DISTANCE_KM','VOLTAGE_LEVEL') AS REQUIRED_COLS
    UNION ALL
    SELECT 'FLUX_OPS_CENTER_TOPOLOGY_METRO',
           'backend/server_fastapi.py /api/topology/metro',
           ARRAY_CONSTRUCT('SUBSTATION_ID','SUBSTATION_NAME','LATITUDE','LONGITUDE',
                           'CAPACITY_MVA','AVG_LOAD_PCT','ACTIVE_OUTAGES',
                           'TRANSFORMER_COUNT','TOTAL_CAPACITY_KVA')
    UNION ALL
    SELECT 'FLUX_OPS_CENTER_TOPOLOGY_NODES',
           'backend/scripts/sync_snowflake_to_postgres.py sync_topology',
           ARRAY_CONSTRUCT('ASSET_ID','ASSET_TYPE','SUBSTATION_ID','CIRCUIT_ID',
                           'FEEDER_ID','LATITUDE','LONGITUDE','STATUS','VOLTAGE_KV')
),
expanded AS (
    SELECT c.VIEW_NAME, c.CONSUMER, f.VALUE::VARCHAR AS REQUIRED_COL
      FROM contracts c, LATERAL FLATTEN(input => c.REQUIRED_COLS) f
),
actual AS (
    SELECT TABLE_NAME, COLUMN_NAME
      FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = 'APPLICATIONS'
),
missing AS (
    SELECT e.VIEW_NAME, e.CONSUMER, e.REQUIRED_COL
      FROM expanded e
      LEFT JOIN actual a
             ON a.TABLE_NAME = e.VIEW_NAME AND a.COLUMN_NAME = e.REQUIRED_COL
     WHERE a.COLUMN_NAME IS NULL
)
SELECT 'V5 COLUMN CONTRACTS' AS CHECK_NAME,
       e.VIEW_NAME || '  <-  ' || e.CONSUMER AS DETAIL,
       COUNT(DISTINCT e.REQUIRED_COL) AS REQUIRED_COLS,
       COUNT(DISTINCT m.REQUIRED_COL) AS MISSING_COLS,
       COALESCE(LISTAGG(DISTINCT m.REQUIRED_COL, ', '), '') AS MISSING_DETAIL,
       CASE WHEN COUNT(DISTINCT m.REQUIRED_COL) = 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM expanded e
LEFT JOIN missing m
       ON m.VIEW_NAME = e.VIEW_NAME AND m.REQUIRED_COL = e.REQUIRED_COL
GROUP BY e.VIEW_NAME, e.CONSUMER
ORDER BY e.VIEW_NAME;

-- ---------------------------------------------------------------------------
-- SECTION 6 -- Guard against the RANDOM()-as-float idiom returning
-- Not a data check: a static assertion that Snowflake RANDOM() is still an
-- integer generator, so anyone reading this file understands why bare
-- RANDOM() arithmetic is forbidden in coordinate expressions.
-- ---------------------------------------------------------------------------
SELECT 'V6 RANDOM() IS NOT A UNIT FLOAT' AS CHECK_NAME,
       'ABS(RANDOM()) should be astronomically larger than 1' AS DETAIL,
       CASE WHEN ABS(RANDOM()) > 1000000 THEN 'PASS'
            ELSE 'FAIL: investigate, RANDOM() semantics changed' END AS STATUS;
