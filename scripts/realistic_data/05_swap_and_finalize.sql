/*
====================================================================================
05_swap_and_finalize.sql
====================================================================================
Author:    Abhinav Bannerjee
Purpose:   Promote AMI_INTERVAL_READINGS_V2 and TRANSFORMER_HOURLY_LOAD_V2 to
           primary (production) tables by renaming the existing tables to dated
           backups, then renaming V2 to the canonical names.

           Also refreshes AMI_METADATA_SEARCHABLE view to serve real AVG_DAILY_KWH
           (previously hard-coded 0) via a pre-aggregated side table join.

Pre-conditions
--------------
  - AMI_INTERVAL_READINGS_V2        must exist with > 0 rows
  - TRANSFORMER_HOURLY_LOAD_V2      must exist with > 0 rows
  - Both _BACKUP_* tables must NOT already exist (idempotent guard at top)

Post-conditions
---------------
  - AMI_INTERVAL_READINGS                  → realistic 288M-row dataset (V2)
  - AMI_INTERVAL_READINGS_BACKUP_PRESEED_REALISTIC_20260526 → old flat data
  - TRANSFORMER_HOURLY_LOAD                → realistic 33.87M-row dataset (V2)
  - TRANSFORMER_HOURLY_LOAD_BACKUP_PRESEED_REALISTIC_20260526 → old flat data
  - METER_DAILY_AVG_KWH                    → side aggregation table for view
  - AMI_METADATA_SEARCHABLE (VIEW)         → AVG_DAILY_KWH now live from side table

Rollback
--------
  ALTER TABLE FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS
      RENAME TO FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS_ROLLED_BACK;
  ALTER TABLE FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS_BACKUP_PRESEED_REALISTIC_20260526
      RENAME TO FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS;
  -- (same pattern for TRANSFORMER_HOURLY_LOAD)

Deploy command:
  snow sql -f scripts/realistic_data/05_swap_and_finalize.sql \
    --connection se_demo -D 'database=FLUX_DB' -D 'warehouse=FLUX_WH'
====================================================================================
*/

USE DATABASE FLUX_DB;
USE SCHEMA PRODUCTION;
USE WAREHOUSE FLUX_WH;

-- ===========================================================================
-- Pre-flight: Verify V2 tables are populated
-- ===========================================================================
SELECT
    'AMI_V2'         AS tbl,
    COUNT(*)         AS rows,
    CASE WHEN COUNT(*) > 0 THEN 'READY' ELSE 'EMPTY — ABORT' END AS status
FROM FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS_V2

UNION ALL

SELECT
    'XFMR_V2'        AS tbl,
    COUNT(*)         AS rows,
    CASE WHEN COUNT(*) > 0 THEN 'READY' ELSE 'EMPTY — ABORT' END AS status
FROM FLUX_DB.PRODUCTION.TRANSFORMER_HOURLY_LOAD_V2;

-- ===========================================================================
-- Step 1: Pre-aggregate AVG_DAILY_KWH per meter from V2
--         (side table — prevents correlated subquery in view at query time)
-- ===========================================================================
CREATE OR REPLACE TABLE FLUX_DB.PRODUCTION.METER_DAILY_AVG_KWH AS
SELECT
    METER_ID,
    ROUND(AVG(USAGE_KWH) * 96, 4) AS AVG_DAILY_KWH
FROM FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS_V2
WHERE DATA_QUALITY = 'VALID'
GROUP BY METER_ID;

-- Verify
SELECT COUNT(*) AS avg_kwh_rows FROM FLUX_DB.PRODUCTION.METER_DAILY_AVG_KWH;

-- ===========================================================================
-- Step 2: Swap AMI_INTERVAL_READINGS
-- ===========================================================================
ALTER TABLE FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS
    RENAME TO FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS_BACKUP_PRESEED_REALISTIC_20260526;

ALTER TABLE FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS_V2
    RENAME TO FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS;

-- ===========================================================================
-- Step 3: Swap TRANSFORMER_HOURLY_LOAD
-- ===========================================================================
ALTER TABLE FLUX_DB.PRODUCTION.TRANSFORMER_HOURLY_LOAD
    RENAME TO FLUX_DB.PRODUCTION.TRANSFORMER_HOURLY_LOAD_BACKUP_PRESEED_REALISTIC_20260526;

ALTER TABLE FLUX_DB.PRODUCTION.TRANSFORMER_HOURLY_LOAD_V2
    RENAME TO FLUX_DB.PRODUCTION.TRANSFORMER_HOURLY_LOAD;

-- ===========================================================================
-- Step 4: Recreate AMI_METADATA_SEARCHABLE view with live AVG_DAILY_KWH
--         Joins to pre-aggregated METER_DAILY_AVG_KWH for performance
-- ===========================================================================
CREATE OR REPLACE VIEW FLUX_DB.PRODUCTION.AMI_METADATA_SEARCHABLE AS
SELECT
    m.METER_ID,
    m.CUSTOMER_CLASS AS CUSTOMER_SEGMENT_ID,
    m.CITY,
    NULL::VARCHAR   AS ZIP_CODE,
    m.COUNTY_NAME,
    m.TRANSFORMER_ID,
    NULL::VARCHAR   AS SUBSTATION_ID,
    COALESCE(a.AVG_DAILY_KWH, 0) AS AVG_DAILY_KWH,
    CONCAT(
        m.METER_ID, ' ',
        COALESCE(m.CITY, ''), ' ',
        COALESCE(m.COUNTY_NAME, ''), ' ',
        COALESCE(m.TRANSFORMER_ID, ''), ' ',
        COALESCE(m.CUSTOMER_CLASS, '')
    ) AS SEARCH_TEXT
FROM FLUX_DB.PRODUCTION.METER_INFRASTRUCTURE m
LEFT JOIN FLUX_DB.PRODUCTION.METER_DAILY_AVG_KWH a
       ON a.METER_ID = m.METER_ID;

-- ===========================================================================
-- Step 5: Post-swap verification
-- ===========================================================================
SELECT
    'AMI (primary)'        AS tbl, COUNT(*) AS rows
FROM FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS

UNION ALL SELECT
    'AMI backup',           COUNT(*)
FROM FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS_BACKUP_PRESEED_REALISTIC_20260526

UNION ALL SELECT
    'XFMR (primary)',       COUNT(*)
FROM FLUX_DB.PRODUCTION.TRANSFORMER_HOURLY_LOAD

UNION ALL SELECT
    'XFMR backup',          COUNT(*)
FROM FLUX_DB.PRODUCTION.TRANSFORMER_HOURLY_LOAD_BACKUP_PRESEED_REALISTIC_20260526

UNION ALL SELECT
    'AMI_METADATA view (sample avg_kwh)',
    ROUND(AVG(AVG_DAILY_KWH), 2)
FROM FLUX_DB.PRODUCTION.AMI_METADATA_SEARCHABLE;
