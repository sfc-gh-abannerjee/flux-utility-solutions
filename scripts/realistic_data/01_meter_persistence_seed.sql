/*
====================================================================================
01_meter_persistence_seed.sql
====================================================================================
Author:    Abhinav Bannerjee
Purpose:   Seed deterministic per-meter persona table that drives realistic AMI
           consumption. Each meter gets a stable home_size_factor, special-load
           flags (solar/EV/pool), microclimate offset (lat-derived), baseline kWh
           (class-derived), and baseline power factor (class-derived).

Why this exists
---------------
The legacy GENERATE_AMI_BATCH (AMI_MIGRATION_DDL.sql:1043-1099) used uniform
random per-row noise with no per-meter persistence. Result: every meter looked
identical day to day (variance < 0.2%). This seed pins each meter to a stable
"persona" so household A is consistently a heavier user than household B across
all 30 days, and special loads (solar, EV, pool pumps) survive aggregation.

All randomness is derived from HASH(METER_ID || salt) so the table is
fully reproducible — running it twice on the same meter set yields identical rows.

Connection / context
--------------------
USE ROLE       SYSADMIN;
USE WAREHOUSE  FLUX_WH;
USE DATABASE   FLUX_DB;
USE SCHEMA     PRODUCTION;
====================================================================================
*/

USE DATABASE FLUX_DB;
USE SCHEMA PRODUCTION;
USE WAREHOUSE FLUX_WH;

CREATE OR REPLACE TABLE METER_PERSONA_PARAMS (
    METER_ID                VARCHAR(50) PRIMARY KEY,
    CUSTOMER_CLASS          VARCHAR(50),
    LATITUDE                FLOAT,
    LONGITUDE               FLOAT,
    COUNTY_NAME             VARCHAR(50),
    HOME_SIZE_FACTOR        NUMBER(5,3),       -- 0.70 - 1.30, deterministic
    HAS_SOLAR               BOOLEAN,
    HAS_EV                  BOOLEAN,
    HAS_POOL_PUMP           BOOLEAN,
    MICROCLIMATE_OFFSET_F   NUMBER(4,2),       -- effective T_F adjustment by latitude band
    PF_BASE                 NUMBER(5,3),       -- baseline power factor by class
    BASE_PER_15MIN          NUMBER(6,3)        -- baseline kWh per 15-min slot by class
);

INSERT INTO METER_PERSONA_PARAMS
SELECT
    m.METER_ID,
    m.CUSTOMER_CLASS,
    m.LATITUDE,
    m.LONGITUDE,
    m.COUNTY_NAME,

    -- Home size factor: deterministic pseudo-uniform 0.70 .. 1.30 from HASH
    ROUND(0.70 + 0.60 * (ABS(HASH(m.METER_ID || '_size')) % 10000) / 10000.0, 3)
        AS HOME_SIZE_FACTOR,

    -- Solar adoption (deterministic): HIGH 10%, UPPER_MIDDLE 4%, MIDDLE 1%
    CASE m.CUSTOMER_CLASS
        WHEN 'HIGH_INCOME'   THEN (ABS(HASH(m.METER_ID || '_solar')) % 100) < 10
        WHEN 'UPPER_MIDDLE'  THEN (ABS(HASH(m.METER_ID || '_solar')) % 100) < 4
        WHEN 'MIDDLE_INCOME' THEN (ABS(HASH(m.METER_ID || '_solar')) % 100) < 1
        ELSE FALSE
    END AS HAS_SOLAR,

    -- EV adoption: HIGH 15%, UPPER 8%, MIDDLE 3%
    CASE m.CUSTOMER_CLASS
        WHEN 'HIGH_INCOME'   THEN (ABS(HASH(m.METER_ID || '_ev')) % 100) < 15
        WHEN 'UPPER_MIDDLE'  THEN (ABS(HASH(m.METER_ID || '_ev')) % 100) < 8
        WHEN 'MIDDLE_INCOME' THEN (ABS(HASH(m.METER_ID || '_ev')) % 100) < 3
        ELSE FALSE
    END AS HAS_EV,

    -- Pool pump adoption (Texas suburbs): HIGH 25%, UPPER/MIDDLE 12% if lat>29.7
    CASE
        WHEN m.LATITUDE > 29.7 AND m.CUSTOMER_CLASS = 'HIGH_INCOME'
            THEN (ABS(HASH(m.METER_ID || '_pool')) % 100) < 25
        WHEN m.LATITUDE > 29.7 AND m.CUSTOMER_CLASS IN ('UPPER_MIDDLE','MIDDLE_INCOME')
            THEN (ABS(HASH(m.METER_ID || '_pool')) % 100) < 12
        ELSE FALSE
    END AS HAS_POOL_PUMP,

    -- Microclimate offset: north suburbs cooler, coastal warmer
    ROUND(CASE
        WHEN m.LATITUDE >= 30.10 THEN -2.5    -- far north (Conroe, New Caney)
        WHEN m.LATITUDE >= 29.95 THEN -1.5    -- north suburbs (Spring, Kingwood, Humble)
        WHEN m.LATITUDE >= 29.75 THEN -0.5    -- inner Houston
        WHEN m.LATITUDE <= 29.50 THEN  1.5    -- coastal (Galveston, League City, Friendswood)
        ELSE  0.0
    END, 2) AS MICROCLIMATE_OFFSET_F,

    -- Power factor by class
    CASE m.CUSTOMER_CLASS
        WHEN 'IND_HEAVY' THEN 0.85
        WHEN 'IND_LIGHT' THEN 0.88
        WHEN 'COM_LARGE' THEN 0.92
        WHEN 'COM_SMALL' THEN 0.95
        ELSE 0.97   -- residential, government
    END AS PF_BASE,

    -- Baseline kWh per 15-min slot by class (sets segment ordering)
    CASE m.CUSTOMER_CLASS
        WHEN 'LOW_INCOME'    THEN 0.18
        WHEN 'LOWER_MIDDLE'  THEN 0.30
        WHEN 'MIDDLE_INCOME' THEN 0.45
        WHEN 'UPPER_MIDDLE'  THEN 0.65
        WHEN 'HIGH_INCOME'   THEN 0.95
        WHEN 'COM_SMALL'     THEN 0.85
        WHEN 'COM_LARGE'     THEN 4.50
        WHEN 'IND_LIGHT'     THEN 7.00
        WHEN 'IND_HEAVY'     THEN 45.00
        WHEN 'GOV_LOCAL'     THEN 1.60
        WHEN 'GOV_STATE'     THEN 2.20
        ELSE 0.50
    END AS BASE_PER_15MIN

FROM METER_INFRASTRUCTURE m;

-- Quick sanity report
SELECT
    CUSTOMER_CLASS,
    COUNT(*) AS meters,
    ROUND(AVG(HOME_SIZE_FACTOR), 3) AS avg_home_size,
    SUM(IFF(HAS_SOLAR,    1, 0)) AS solar_count,
    SUM(IFF(HAS_EV,       1, 0)) AS ev_count,
    SUM(IFF(HAS_POOL_PUMP,1, 0)) AS pool_count,
    ROUND(AVG(MICROCLIMATE_OFFSET_F), 2) AS avg_micro_offset,
    AVG(BASE_PER_15MIN) AS base_per_15min
FROM METER_PERSONA_PARAMS
GROUP BY 1
ORDER BY base_per_15min DESC;
