-- ============================================================================
-- FLUX UTILITY SOLUTIONS - POSTGRESQL SEED DATA LOADING
-- ============================================================================
-- This script loads seed data from CSV files into PostgreSQL tables.
--
-- USAGE:
--   psql -h localhost -U postgres -d flux_ops -f seed_data/postgresql/02_load_data.sql
--
-- PREREQUISITES:
--   1. Run 01_schema.sql first to create tables
--   2. CSV files must be in seed_data/csv/ directory
-- ============================================================================

SET search_path TO production, public;

-- ============================================================================
-- LOAD SUBSTATIONS
-- ============================================================================
\echo 'Loading SUBSTATIONS...'

COPY substations (
    substation_id,
    substation_name,
    latitude,
    longitude,
    capacity_mva,
    region,
    voltage_level,
    commissioned_date,
    operational_status,
    substation_type
)
FROM PROGRAM 'cat seed_data/csv/substations.csv'
WITH (FORMAT CSV, HEADER TRUE, NULL '');

SELECT 'Loaded ' || COUNT(*) || ' substations' AS status FROM substations;

-- ============================================================================
-- LOAD TRANSFORMER_METADATA
-- ============================================================================
\echo 'Loading TRANSFORMER_METADATA...'

-- Temporarily disable FK constraints for loading
ALTER TABLE transformer_metadata DROP CONSTRAINT IF EXISTS transformer_metadata_substation_id_fkey;

COPY transformer_metadata (
    transformer_id,
    substation_id,
    circuit_id,
    latitude,
    longitude,
    rated_kva,
    install_year,
    last_maintenance_date,
    current_load_kva,
    peak_load_kva,
    load_utilization_pct,
    meter_count,
    health_score,
    manufacturer,
    model_number
)
FROM PROGRAM 'cat seed_data/csv/transformers.csv'
WITH (FORMAT CSV, HEADER TRUE, NULL '');

SELECT 'Loaded ' || COUNT(*) || ' transformers' AS status FROM transformer_metadata;

-- ============================================================================
-- LOAD METER_INFRASTRUCTURE
-- ============================================================================
\echo 'Loading METER_INFRASTRUCTURE...'

-- Temporarily disable FK constraints
ALTER TABLE meter_infrastructure DROP CONSTRAINT IF EXISTS meter_infrastructure_transformer_id_fkey;
ALTER TABLE meter_infrastructure DROP CONSTRAINT IF EXISTS meter_infrastructure_substation_id_fkey;

COPY meter_infrastructure (
    meter_id,
    meter_latitude,
    meter_longitude,
    meter_type,
    transformer_id,
    substation_id,
    circuit_id,
    health_score,
    commissioned_date,
    city,
    zip_code,
    customer_segment_id
)
FROM PROGRAM 'cat seed_data/csv/meters.csv'
WITH (FORMAT CSV, HEADER TRUE, NULL '');

SELECT 'Loaded ' || COUNT(*) || ' meters' AS status FROM meter_infrastructure;

-- ============================================================================
-- LOAD CUSTOMERS_MASTER_DATA
-- ============================================================================
\echo 'Loading CUSTOMERS_MASTER_DATA...'

-- Temporarily disable FK constraints
ALTER TABLE customers_master_data DROP CONSTRAINT IF EXISTS customers_master_data_primary_meter_id_fkey;

COPY customers_master_data (
    customer_id,
    first_name,
    last_name,
    full_name,
    primary_meter_id,
    customer_segment,
    service_address,
    service_county,
    city,
    zip_code,
    phone,
    email,
    account_status,
    service_start_date
)
FROM PROGRAM 'cat seed_data/csv/customers.csv'
WITH (FORMAT CSV, HEADER TRUE, NULL '');

SELECT 'Loaded ' || COUNT(*) || ' customers' AS status FROM customers_master_data;

-- ============================================================================
-- GENERATE AMI READINGS (Synthetic time-series data)
-- ============================================================================
\echo 'Generating AMI readings (7 days of hourly data)...'

-- Generate timestamps for past 7 days (hourly)
WITH timestamps AS (
    SELECT generate_series(
        NOW() - INTERVAL '7 days',
        NOW(),
        INTERVAL '1 hour'
    ) AS reading_time
),
meter_readings AS (
    SELECT 
        m.meter_id,
        t.reading_time,
        ROUND(
            CASE 
                WHEN m.customer_segment_id = 'RESIDENTIAL' THEN 0.8
                WHEN m.customer_segment_id = 'COMMERCIAL' THEN 2.5
                WHEN m.customer_segment_id = 'INDUSTRIAL' THEN 8.0
                ELSE 1.0
            END
            * CASE 
                WHEN EXTRACT(HOUR FROM t.reading_time) BETWEEN 6 AND 9 THEN 1.3
                WHEN EXTRACT(HOUR FROM t.reading_time) BETWEEN 17 AND 21 THEN 1.5
                WHEN EXTRACT(HOUR FROM t.reading_time) BETWEEN 0 AND 5 THEN 0.4
                ELSE 1.0
            END
            * (0.8 + RANDOM() * 0.4)
        ::NUMERIC, 3) AS reading_kwh,
        'INTERVAL' AS reading_type,
        CASE WHEN RANDOM() < 0.98 THEN 'VALID' ELSE 'ESTIMATED' END AS quality_flag
    FROM meter_infrastructure m
    CROSS JOIN timestamps t
)
INSERT INTO ami_readings (meter_id, reading_timestamp, reading_value_kwh, reading_type, quality_flag)
SELECT meter_id, reading_time, reading_kwh, reading_type, quality_flag
FROM meter_readings;

SELECT 'Generated ' || COUNT(*) || ' AMI readings' AS status FROM ami_readings;

-- ============================================================================
-- SUMMARY
-- ============================================================================
\echo ''
\echo '=== SEED DATA LOADING COMPLETE ==='
\echo ''

SELECT 'substations' AS table_name, COUNT(*) AS row_count FROM substations
UNION ALL
SELECT 'transformer_metadata', COUNT(*) FROM transformer_metadata
UNION ALL
SELECT 'meter_infrastructure', COUNT(*) FROM meter_infrastructure
UNION ALL
SELECT 'customers_master_data', COUNT(*) FROM customers_master_data
UNION ALL
SELECT 'ami_readings', COUNT(*) FROM ami_readings
ORDER BY table_name;
