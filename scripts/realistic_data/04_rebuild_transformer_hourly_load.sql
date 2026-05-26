/*
====================================================================================
04_rebuild_transformer_hourly_load.sql
====================================================================================
Author:    Abhinav Bannerjee
Purpose:   Rebuild TRANSFORMER_HOURLY_LOAD_V2 by aggregating AMI_INTERVAL_READINGS_V2
           into hourly transformer load summaries with realistic load factors and
           temperature-adjusted thermal estimates.

Formula notes
-------------
CURRENT_LOAD_KW  = SUM(USAGE_KWH × 4) — sum of instantaneous kW across all meters
                   and all 15-min intervals within the hour, per transformer.
LOAD_FACTOR_PCT  = CURRENT_LOAD_KW / (CAPACITY_KVA × 0.95) × 100
                   — 0.95 = nameplate-to-operating derate factor.
TEMPERATURE_C    = ambient_C + (LOAD_FACTOR_PCT / 100) × 35
                   — 35°C max thermal rise at 100% load factor.
                   ambient_C = (TEMPERATURE_F − 32) × 5/9 from HOUSTON_WEATHER_HOURLY.

Expected row count: 47,048 transformers × 720 hours = 33,874,560

Deploy command:
  snow sql -f scripts/realistic_data/04_rebuild_transformer_hourly_load.sql \
    --connection se_demo -D 'database=FLUX_DB' -D 'warehouse=FLUX_WH'
====================================================================================
*/

USE DATABASE FLUX_DB;
USE SCHEMA PRODUCTION;
USE WAREHOUSE FLUX_WH;

-- ===========================================================================
-- Create V2 target table — explicit DDL with wider column types.
-- NOTE: Using explicit DDL (not LIKE) because the original LOAD_FACTOR_PCT
-- was NUMBER(5,2) (max 999.99) which overflows when heavy industrial meters
-- (BASE_PER_15MIN=45) land on small transformers.  V2 uses NUMBER(10,4).
-- ===========================================================================
CREATE OR REPLACE TABLE FLUX_DB.PRODUCTION.TRANSFORMER_HOURLY_LOAD_V2 (
    TRANSFORMER_ID  TEXT          NOT NULL,
    LOAD_HOUR       TIMESTAMP_NTZ NOT NULL,
    CURRENT_LOAD_KW NUMBER(14, 4),
    LOAD_FACTOR_PCT NUMBER(10, 4),
    TEMPERATURE_C   NUMBER(10, 4)
);

-- ===========================================================================
-- Build hourly aggregation from AMI_INTERVAL_READINGS_V2
-- ===========================================================================
INSERT INTO FLUX_DB.PRODUCTION.TRANSFORMER_HOURLY_LOAD_V2 (
    TRANSFORMER_ID,
    LOAD_HOUR,
    CURRENT_LOAD_KW,
    LOAD_FACTOR_PCT,
    TEMPERATURE_C
)
WITH

-- Hourly weather lookup (one row per hour for July 2024)
hourly_weather AS (
    SELECT
        OBSERVATION_TIME                                        AS obs_hour,
        (COALESCE(TEMPERATURE_F, 85.0) - 32.0) * 5.0 / 9.0   AS ambient_c
    FROM FLUX_DB.PRODUCTION.HOUSTON_WEATHER_HOURLY
),

-- Aggregate AMI readings to transformer-hour level
ami_agg AS (
    SELECT
        mi.TRANSFORMER_ID,
        DATE_TRUNC('HOUR', r.READING_TIMESTAMP)     AS load_hour,
        -- kW instantaneous per interval = USAGE_KWH × 4; sum over all meters + slots
        ROUND(SUM(r.USAGE_KWH * 4.0), 4)            AS current_load_kw
    FROM FLUX_DB.PRODUCTION.AMI_INTERVAL_READINGS_V2 r
    JOIN FLUX_DB.PRODUCTION.METER_INFRASTRUCTURE mi
      ON mi.METER_ID = r.METER_ID
    WHERE mi.TRANSFORMER_ID IS NOT NULL
    GROUP BY
        mi.TRANSFORMER_ID,
        DATE_TRUNC('HOUR', r.READING_TIMESTAMP)
)

SELECT
    a.TRANSFORMER_ID,
    a.load_hour                                         AS LOAD_HOUR,
    a.current_load_kw                                   AS CURRENT_LOAD_KW,

    -- Load factor: normalised to transformer nameplate × 0.95 derate
    ROUND(
        a.current_load_kw
        / NULLIF(tm.CAPACITY_KVA * 0.95, 0)
        * 100.0,
        4
    )                                                   AS LOAD_FACTOR_PCT,

    -- Thermal estimate: ambient + proportional rise (35°C at 100% load)
    ROUND(
        COALESCE(w.ambient_c, (85.0 - 32.0) * 5.0 / 9.0)
        + (
            a.current_load_kw
            / NULLIF(tm.CAPACITY_KVA * 0.95, 0)
          ) * 35.0,
        4
    )                                                   AS TEMPERATURE_C

FROM ami_agg a
LEFT JOIN FLUX_DB.PRODUCTION.TRANSFORMER_METADATA tm
       ON tm.TRANSFORMER_ID = a.TRANSFORMER_ID
LEFT JOIN hourly_weather w
       ON w.obs_hour = a.load_hour;

-- ===========================================================================
-- Quick sanity report
-- ===========================================================================
SELECT
    COUNT(*)                            AS total_rows,
    COUNT(DISTINCT TRANSFORMER_ID)      AS transformers,
    COUNT(DISTINCT LOAD_HOUR)           AS hours,
    ROUND(AVG(CURRENT_LOAD_KW), 2)      AS avg_load_kw,
    ROUND(MAX(CURRENT_LOAD_KW), 2)      AS max_load_kw,
    ROUND(AVG(LOAD_FACTOR_PCT), 2)      AS avg_load_factor_pct,
    ROUND(AVG(TEMPERATURE_C), 2)        AS avg_temp_c
FROM FLUX_DB.PRODUCTION.TRANSFORMER_HOURLY_LOAD_V2;
