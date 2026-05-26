/*
====================================================================================
03_generate_ami_realistic.sql
====================================================================================
Author:    Abhinav Bannerjee
Purpose:   Generate AMI_INTERVAL_READINGS_V2 with realistic temporal, segment,
           and geographic variance, fully correlated with grid topology, weather,
           and Hurricane Beryl outages.

Replaces  GENERATE_AMI_BATCH (AMI_MIGRATION_DDL.sql:1043-1099) which produced
          flat data (<0.2% daily variance, no segment differentiation, no
          weekday/weekend pattern, no real weather correlation, no outages).

Realism factors (every meter, every 15-min slot)
------------------------------------------------
1. base_per_class             — baseline kWh by CUSTOMER_CLASS (segment ordering)
2. diurnal_curve(class, hour) — per-class hour-of-day multiplier
3. hvac_factor(weather, geo)  — joins HOUSTON_WEATHER_HOURLY, lat-derived microclimate
4. dow_factor(class, dow)     — weekday/weekend behavior by class
5. holiday_factor (July 4)    — residential up, commercial/industrial/gov down
6. beryl_pre_factor           — pre-storm spike 07/07 - 07/08 02:00 for affected lat
7. home_size_factor           — deterministic per-meter home-size (consistent across days)
8. solar_factor               — HAS_SOLAR meters: 10AM-4PM × 0.55
9. ev_add                     — HAS_EV meters: +0.40 kWh per 15-min during 23:00-05:00
10. pool_add                  — HAS_POOL_PUMP: +0.25 kWh per 15-min during 04:00-07:00
11. lognormal_noise           — EXP(NORMAL(0, 0.13)) for realistic right-skewed residuals
12. outage_indicator          — 0 for (transformer, timestamp) pairs in active outage

Voltage / Current / PF derived from USAGE_KWH and PF_BASE for physical consistency.

Connection / context
--------------------
USE ROLE       SYSADMIN;
USE WAREHOUSE  FLUX_WH;     -- size up to XL before running, back to MEDIUM after
USE DATABASE   FLUX_DB;
USE SCHEMA     PRODUCTION;

Expected runtime: ~10-15 min on XL, ~$5-8 in credits.
====================================================================================
*/

USE DATABASE FLUX_DB;
USE SCHEMA PRODUCTION;
USE WAREHOUSE FLUX_WH;

-- ===========================================================================
-- Size up for the regen window
-- ===========================================================================
ALTER WAREHOUSE FLUX_WH SET WAREHOUSE_SIZE = 'XLARGE';

-- ===========================================================================
-- V2 target table — same DDL as live AMI_INTERVAL_READINGS
-- ===========================================================================
CREATE OR REPLACE TABLE AMI_INTERVAL_READINGS_V2
    CLUSTER BY (DATE_TRUNC('DAY', READING_TIMESTAMP), METER_ID)
AS SELECT * FROM AMI_INTERVAL_READINGS WHERE 1=0;

-- ===========================================================================
-- Pre-build time series (2880 15-min slots covering July 2024)
-- ===========================================================================
CREATE OR REPLACE TEMPORARY TABLE TIME_SERIES_15MIN AS
SELECT
    DATEADD(minute, 15 * (ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1),
            '2024-07-01 00:00:00'::TIMESTAMP_NTZ) AS reading_ts
FROM TABLE(GENERATOR(ROWCOUNT => 30 * 96));   -- 2880 rows

-- ===========================================================================
-- Pre-build outage intervals from REAL OUTAGE_RESTORATION_TRACKER
-- (loaded from flux-utility-solutions/seed_data/full/outage_events/ parquet,
-- filtered to transformers that exist in PRODUCTION.TRANSFORMER_METADATA).
-- Explicit (transformer_id, reading_ts) pairs supports cheap equality LEFT JOIN.
-- DISTINCT: prevents duplicate rows when a transformer has multiple overlapping
-- outage records in OUTAGE_RESTORATION_TRACKER — without DISTINCT, the LEFT JOIN
-- in the main INSERT multiplies rows (observed: +19,745 extras on 288M base).
-- ===========================================================================
CREATE OR REPLACE TEMPORARY TABLE OUTAGE_INTERVALS_15MIN AS
SELECT DISTINCT
    o.TRANSFORMER_ID,
    t.reading_ts
FROM OUTAGE_RESTORATION_TRACKER o
JOIN TIME_SERIES_15MIN t
  ON t.reading_ts BETWEEN o.OUTAGE_START_TIME AND o.OUTAGE_END_TIME
WHERE o.TRANSFORMER_ID IS NOT NULL
  AND o.OUTAGE_START_TIME >= '2024-07-01'::TIMESTAMP_NTZ
  AND o.OUTAGE_START_TIME <  '2024-08-01'::TIMESTAMP_NTZ;

-- ===========================================================================
-- Main INSERT — single statement, ~288M rows
-- ===========================================================================
INSERT INTO AMI_INTERVAL_READINGS_V2 (
    READING_ID, METER_ID, READING_TIMESTAMP,
    USAGE_KWH, VOLTAGE_V, CURRENT_A, POWER_FACTOR, DATA_QUALITY
)
WITH
weather_15min AS (
    SELECT
        t.reading_ts,
        w.TEMPERATURE_F,
        w.HUMIDITY_PCT
    FROM TIME_SERIES_15MIN t
    LEFT JOIN HOUSTON_WEATHER_HOURLY w
      ON DATE_TRUNC('HOUR', t.reading_ts) = w.OBSERVATION_TIME
),
meter_persona AS (
    SELECT
        m.METER_ID,
        m.TRANSFORMER_ID,
        m.LATITUDE,
        m.CUSTOMER_CLASS,
        p.HOME_SIZE_FACTOR,
        p.HAS_SOLAR,
        p.HAS_EV,
        p.HAS_POOL_PUMP,
        p.MICROCLIMATE_OFFSET_F,
        p.PF_BASE,
        p.BASE_PER_15MIN,
        -- coarse class bucket for branching
        CASE
            WHEN m.CUSTOMER_CLASS IN ('LOW_INCOME','LOWER_MIDDLE','MIDDLE_INCOME','UPPER_MIDDLE','HIGH_INCOME')
                THEN 'RES'
            WHEN m.CUSTOMER_CLASS IN ('COM_SMALL','COM_LARGE')          THEN 'COM'
            WHEN m.CUSTOMER_CLASS IN ('IND_LIGHT','IND_HEAVY')          THEN 'IND'
            WHEN m.CUSTOMER_CLASS IN ('GOV_LOCAL','GOV_STATE')          THEN 'GOV'
            ELSE 'RES'
        END AS CLASS_BUCKET
    FROM METER_INFRASTRUCTURE m
    JOIN METER_PERSONA_PARAMS p USING (METER_ID)
)
SELECT
    UUID_STRING() AS READING_ID,
    mp.METER_ID,
    ts.reading_ts AS READING_TIMESTAMP,

    -- ====================================================================
    -- USAGE_KWH formula
    -- ====================================================================
    ROUND(
      CASE
        -- ───── Outage: meter's transformer in active outage window ─────
        WHEN oi.TRANSFORMER_ID IS NOT NULL THEN 0.000
        ELSE
          (
            mp.BASE_PER_15MIN

            -- 1. diurnal_mult by (class_bucket, hour) ──────────────
            * CASE mp.CLASS_BUCKET
                WHEN 'RES' THEN
                    CASE EXTRACT(HOUR FROM ts.reading_ts)
                        WHEN 0 THEN 0.55 WHEN 1 THEN 0.55 WHEN 2 THEN 0.55 WHEN 3 THEN 0.55
                        WHEN 4 THEN 0.60 WHEN 5 THEN 0.65 WHEN 6 THEN 1.10 WHEN 7 THEN 1.30
                        WHEN 8 THEN 1.20 WHEN 9 THEN 0.95 WHEN 10 THEN 0.85 WHEN 11 THEN 0.85
                        WHEN 12 THEN 0.85 WHEN 13 THEN 0.85 WHEN 14 THEN 0.85 WHEN 15 THEN 0.85
                        WHEN 16 THEN 1.00 WHEN 17 THEN 1.30 WHEN 18 THEN 1.55 WHEN 19 THEN 1.50
                        WHEN 20 THEN 1.40 WHEN 21 THEN 1.20 WHEN 22 THEN 1.00 WHEN 23 THEN 0.90
                    END
                WHEN 'COM' THEN
                    CASE EXTRACT(HOUR FROM ts.reading_ts)
                        WHEN 0 THEN 0.40 WHEN 1 THEN 0.40 WHEN 2 THEN 0.40 WHEN 3 THEN 0.40
                        WHEN 4 THEN 0.40 WHEN 5 THEN 0.50 WHEN 6 THEN 0.65 WHEN 7 THEN 0.95
                        WHEN 8 THEN 1.20 WHEN 9 THEN 1.30 WHEN 10 THEN 1.35 WHEN 11 THEN 1.35
                        WHEN 12 THEN 1.30 WHEN 13 THEN 1.35 WHEN 14 THEN 1.35 WHEN 15 THEN 1.35
                        WHEN 16 THEN 1.25 WHEN 17 THEN 1.10 WHEN 18 THEN 0.85 WHEN 19 THEN 0.65
                        WHEN 20 THEN 0.55 WHEN 21 THEN 0.50 WHEN 22 THEN 0.45 WHEN 23 THEN 0.40
                    END
                WHEN 'IND' THEN
                    CASE
                        WHEN EXTRACT(HOUR FROM ts.reading_ts) BETWEEN 0 AND 5  THEN 0.85
                        WHEN EXTRACT(HOUR FROM ts.reading_ts) BETWEEN 22 AND 23 THEN 0.90
                        ELSE 1.05
                    END
                WHEN 'GOV' THEN
                    CASE
                        WHEN EXTRACT(HOUR FROM ts.reading_ts) BETWEEN 8 AND 17  THEN 1.30
                        WHEN EXTRACT(HOUR FROM ts.reading_ts) IN (7, 18, 19)    THEN 0.50
                        ELSE 0.20
                    END
              END

            -- 2. HVAC factor (real weather + microclimate) ──────────
            * (
                1.0
                + CASE mp.CLASS_BUCKET
                    WHEN 'RES' THEN 0.028
                    WHEN 'COM' THEN 0.020
                    WHEN 'IND' THEN 0.008
                    WHEN 'GOV' THEN 0.020
                  END
                  * GREATEST(0, COALESCE(w.TEMPERATURE_F, 85) + mp.MICROCLIMATE_OFFSET_F - 72)
                + CASE mp.CLASS_BUCKET
                    WHEN 'RES' THEN 0.020
                    WHEN 'COM' THEN 0.012
                    WHEN 'IND' THEN 0.005
                    WHEN 'GOV' THEN 0.012
                  END
                  * GREATEST(0, 60 - (COALESCE(w.TEMPERATURE_F, 85) + mp.MICROCLIMATE_OFFSET_F))
                + CASE mp.CLASS_BUCKET
                    WHEN 'RES' THEN 0.0008 * (COALESCE(w.HUMIDITY_PCT, 70) - 50)
                    WHEN 'COM' THEN 0.0005 * (COALESCE(w.HUMIDITY_PCT, 70) - 50)
                    ELSE 0
                  END
              )

            -- 3. DOW factor ─────────────────────────────────────────
            * CASE mp.CLASS_BUCKET
                WHEN 'RES' THEN
                    CASE DAYNAME(ts.reading_ts)
                        WHEN 'Sun' THEN 1.10
                        WHEN 'Sat' THEN 1.07
                        ELSE 1.00
                    END
                WHEN 'COM' THEN
                    CASE DAYNAME(ts.reading_ts)
                        WHEN 'Sun' THEN 0.40
                        WHEN 'Sat' THEN 0.55
                        ELSE 1.00
                    END
                WHEN 'IND' THEN
                    CASE WHEN DAYNAME(ts.reading_ts) IN ('Sat','Sun') THEN 0.85 ELSE 1.00 END
                WHEN 'GOV' THEN
                    CASE WHEN DAYNAME(ts.reading_ts) IN ('Sat','Sun') THEN 0.30 ELSE 1.00 END
              END

            -- 4. Holiday (July 4) ──────────────────────────────────
            * CASE
                WHEN DATE(ts.reading_ts) = '2024-07-04' THEN
                    CASE mp.CLASS_BUCKET
                        WHEN 'RES' THEN 1.18
                        WHEN 'COM' THEN 0.45
                        WHEN 'IND' THEN 0.55
                        WHEN 'GOV' THEN 0.30
                    END
                ELSE 1.00
              END

            -- 5. Beryl pre-storm spike ────────────────────────────
            * CASE
                WHEN ts.reading_ts BETWEEN '2024-07-07 00:00:00'::TIMESTAMP_NTZ
                                       AND '2024-07-08 02:00:00'::TIMESTAMP_NTZ
                     AND mp.LATITUDE < 29.95 THEN 1.15
                ELSE 1.00
              END

            -- 6. Home size factor (per-meter persistent) ──────────
            * mp.HOME_SIZE_FACTOR

            -- 7. Solar net-metering factor (10AM-4PM only) ────────
            * CASE
                WHEN mp.HAS_SOLAR
                     AND EXTRACT(HOUR FROM ts.reading_ts) BETWEEN 10 AND 16
                THEN 0.55
                ELSE 1.00
              END

            -- 8. Lognormal noise ──────────────────────────────────
            * EXP(NORMAL(0, 0.13, RANDOM()))

          )
          -- 9. EV charging additive load (11PM - 5AM) ─────────────
          + CASE
              WHEN mp.HAS_EV
                   AND (EXTRACT(HOUR FROM ts.reading_ts) >= 23
                        OR EXTRACT(HOUR FROM ts.reading_ts) <= 5)
              THEN 0.40
              ELSE 0
            END

          -- 10. Pool pump additive load (4-7 AM) ────────────────
          + CASE
              WHEN mp.HAS_POOL_PUMP
                   AND EXTRACT(HOUR FROM ts.reading_ts) BETWEEN 4 AND 7
              THEN 0.25
              ELSE 0
            END
      END,
      4
    ) AS USAGE_KWH,

    -- ====================================================================
    -- VOLTAGE_V — sag under heavy local load
    -- ====================================================================
    ROUND(
        CASE WHEN oi.TRANSFORMER_ID IS NOT NULL THEN 0.0
             ELSE 120.0
                  - 4.0 * (mp.BASE_PER_15MIN / 5.0)             -- coarse load proxy
                  + NORMAL(0, 0.8, RANDOM())
        END,
    2) AS VOLTAGE_V,

    -- ====================================================================
    -- CURRENT_A — derived from kWh and voltage and PF for physical consistency
    -- ====================================================================
    ROUND(
        CASE WHEN oi.TRANSFORMER_ID IS NOT NULL THEN 0.0
             ELSE GREATEST(0.01,
                  -- kWh/15min × 4 = kW; ×1000 = W; / V / PF = A
                  ((mp.BASE_PER_15MIN * mp.HOME_SIZE_FACTOR) * 4 * 1000)
                   / NULLIF(120.0 * mp.PF_BASE, 0)
                  + NORMAL(0, 0.3, RANDOM()))
        END,
    2) AS CURRENT_A,

    -- ====================================================================
    -- POWER_FACTOR — per-class baseline + small per-reading drift
    -- ====================================================================
    ROUND(
        CASE WHEN oi.TRANSFORMER_ID IS NOT NULL THEN 0.000
             ELSE LEAST(0.999, GREATEST(0.700,
                       mp.PF_BASE + NORMAL(0, 0.015, RANDOM())))
        END,
    3) AS POWER_FACTOR,

    -- ====================================================================
    -- DATA_QUALITY — flag outage rows, all others valid
    -- ====================================================================
    CASE WHEN oi.TRANSFORMER_ID IS NOT NULL THEN 'OUTAGE'
         ELSE 'VALID' END AS DATA_QUALITY

FROM meter_persona mp
CROSS JOIN TIME_SERIES_15MIN ts
LEFT JOIN weather_15min w           ON w.reading_ts = ts.reading_ts
LEFT JOIN OUTAGE_INTERVALS_15MIN oi ON oi.TRANSFORMER_ID = mp.TRANSFORMER_ID
                                    AND oi.reading_ts    = ts.reading_ts;

-- ===========================================================================
-- Quick sanity report (full validation in 99_validation.sql)
-- ===========================================================================
SELECT 'V2 row count' AS check_label, COUNT(*) AS n FROM AMI_INTERVAL_READINGS_V2;

SELECT
    DATE(READING_TIMESTAMP) AS day,
    COUNT(DISTINCT METER_ID) AS meters,
    ROUND(AVG(USAGE_KWH) * 96, 2) AS avg_kwh_per_meter_per_day,
    ROUND(STDDEV(USAGE_KWH) / NULLIF(AVG(USAGE_KWH), 0) * 100, 2) AS rel_sd_pct
FROM AMI_INTERVAL_READINGS_V2
WHERE READING_TIMESTAMP < '2024-07-10'
GROUP BY 1 ORDER BY 1;
