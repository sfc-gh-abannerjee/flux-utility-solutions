-- ============================================================================
-- FLUX UTILITY SOLUTIONS - POSTGRESQL SCHEMA SETUP
-- ============================================================================
-- This script creates the PostgreSQL database schema for Flux Ops Center.
-- It mirrors the Snowflake schema structure for hybrid deployments.
--
-- USAGE:
--   psql -h localhost -U postgres -d flux_ops -f seed_data/postgresql/01_schema.sql
-- ============================================================================

-- Create schema
CREATE SCHEMA IF NOT EXISTS production;

-- Set search path
SET search_path TO production, public;

-- ============================================================================
-- SUBSTATIONS TABLE
-- ============================================================================
DROP TABLE IF EXISTS substations CASCADE;
CREATE TABLE substations (
    substation_id VARCHAR(50) PRIMARY KEY,
    substation_name VARCHAR(200) NOT NULL,
    latitude DECIMAL(10, 6),
    longitude DECIMAL(10, 6),
    capacity_mva DECIMAL(12, 2),
    region VARCHAR(100),
    voltage_level VARCHAR(50),
    commissioned_date DATE,
    operational_status VARCHAR(50) DEFAULT 'Operational',
    substation_type VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_substations_region ON substations(region);
CREATE INDEX idx_substations_status ON substations(operational_status);

-- ============================================================================
-- TRANSFORMER_METADATA TABLE
-- ============================================================================
DROP TABLE IF EXISTS transformer_metadata CASCADE;
CREATE TABLE transformer_metadata (
    transformer_id VARCHAR(50) PRIMARY KEY,
    substation_id VARCHAR(50) REFERENCES substations(substation_id),
    circuit_id VARCHAR(50),
    latitude DECIMAL(10, 6),
    longitude DECIMAL(10, 6),
    rated_kva INTEGER,
    install_year INTEGER,
    last_maintenance_date DATE,
    current_load_kva DECIMAL(10, 2),
    peak_load_kva DECIMAL(10, 2),
    load_utilization_pct DECIMAL(5, 2),
    meter_count INTEGER,
    health_score DECIMAL(5, 2),
    manufacturer VARCHAR(100),
    model_number VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_transformer_substation ON transformer_metadata(substation_id);
CREATE INDEX idx_transformer_health ON transformer_metadata(health_score);
CREATE INDEX idx_transformer_circuit ON transformer_metadata(circuit_id);

-- ============================================================================
-- METER_INFRASTRUCTURE TABLE
-- ============================================================================
DROP TABLE IF EXISTS meter_infrastructure CASCADE;
CREATE TABLE meter_infrastructure (
    meter_id VARCHAR(50) PRIMARY KEY,
    meter_latitude DECIMAL(10, 6),
    meter_longitude DECIMAL(10, 6),
    meter_type VARCHAR(50) DEFAULT 'AMI',
    transformer_id VARCHAR(50) REFERENCES transformer_metadata(transformer_id),
    substation_id VARCHAR(50) REFERENCES substations(substation_id),
    circuit_id VARCHAR(50),
    health_score DECIMAL(5, 2),
    commissioned_date DATE,
    city VARCHAR(100),
    zip_code VARCHAR(20),
    customer_segment_id VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_meter_transformer ON meter_infrastructure(transformer_id);
CREATE INDEX idx_meter_substation ON meter_infrastructure(substation_id);
CREATE INDEX idx_meter_segment ON meter_infrastructure(customer_segment_id);
CREATE INDEX idx_meter_city ON meter_infrastructure(city);

-- ============================================================================
-- CUSTOMERS_MASTER_DATA TABLE
-- ============================================================================
DROP TABLE IF EXISTS customers_master_data CASCADE;
CREATE TABLE customers_master_data (
    customer_id VARCHAR(50) PRIMARY KEY,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    full_name VARCHAR(250),
    primary_meter_id VARCHAR(50) REFERENCES meter_infrastructure(meter_id),
    customer_segment VARCHAR(50),
    service_address TEXT,
    service_county VARCHAR(100),
    city VARCHAR(100),
    zip_code VARCHAR(20),
    phone VARCHAR(50),
    email VARCHAR(200),
    account_status VARCHAR(50) DEFAULT 'ACTIVE',
    service_start_date DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_customer_meter ON customers_master_data(primary_meter_id);
CREATE INDEX idx_customer_segment ON customers_master_data(customer_segment);
CREATE INDEX idx_customer_city ON customers_master_data(city);
CREATE INDEX idx_customer_status ON customers_master_data(account_status);

-- ============================================================================
-- AMI_READINGS TABLE (Time-series data)
-- ============================================================================
DROP TABLE IF EXISTS ami_readings CASCADE;
CREATE TABLE ami_readings (
    reading_id BIGSERIAL PRIMARY KEY,
    meter_id VARCHAR(50) REFERENCES meter_infrastructure(meter_id),
    reading_timestamp TIMESTAMP NOT NULL,
    reading_value_kwh DECIMAL(12, 3),
    reading_type VARCHAR(50) DEFAULT 'INTERVAL',
    quality_flag VARCHAR(50) DEFAULT 'VALID',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_ami_meter ON ami_readings(meter_id);
CREATE INDEX idx_ami_timestamp ON ami_readings(reading_timestamp);
CREATE INDEX idx_ami_meter_time ON ami_readings(meter_id, reading_timestamp);

-- ============================================================================
-- OUTAGE_EVENTS TABLE
-- ============================================================================
DROP TABLE IF EXISTS outage_events CASCADE;
CREATE TABLE outage_events (
    event_id VARCHAR(50) PRIMARY KEY,
    substation_id VARCHAR(50) REFERENCES substations(substation_id),
    circuit_id VARCHAR(50),
    event_type VARCHAR(50),
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    affected_customers INTEGER,
    root_cause TEXT,
    resolution_notes TEXT,
    status VARCHAR(50) DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_outage_substation ON outage_events(substation_id);
CREATE INDEX idx_outage_status ON outage_events(status);
CREATE INDEX idx_outage_time ON outage_events(start_time);

-- ============================================================================
-- WORK_ORDERS TABLE
-- ============================================================================
DROP TABLE IF EXISTS work_orders CASCADE;
CREATE TABLE work_orders (
    work_order_id VARCHAR(50) PRIMARY KEY,
    asset_type VARCHAR(50),
    asset_id VARCHAR(50),
    work_type VARCHAR(100),
    priority VARCHAR(50),
    status VARCHAR(50) DEFAULT 'PENDING',
    scheduled_date DATE,
    completion_date DATE,
    assigned_crew VARCHAR(100),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_wo_asset ON work_orders(asset_type, asset_id);
CREATE INDEX idx_wo_status ON work_orders(status);
CREATE INDEX idx_wo_priority ON work_orders(priority);

-- ============================================================================
-- UTILITY VIEWS
-- ============================================================================

-- Transformer load summary view
CREATE OR REPLACE VIEW v_transformer_load_summary AS
SELECT 
    t.transformer_id,
    t.substation_id,
    t.rated_kva,
    t.current_load_kva,
    t.health_score,
    CASE 
        WHEN t.load_utilization_pct > 90 THEN 'CRITICAL'
        WHEN t.load_utilization_pct > 75 THEN 'WARNING'
        ELSE 'NORMAL'
    END AS load_status,
    t.meter_count
FROM transformer_metadata t;

-- Customer summary view
CREATE OR REPLACE VIEW v_customer_summary AS
SELECT 
    c.customer_segment,
    COUNT(*) AS customer_count,
    COUNT(DISTINCT c.city) AS cities_served
FROM customers_master_data c
GROUP BY c.customer_segment;

-- Print completion message
DO $$
BEGIN
    RAISE NOTICE 'PostgreSQL schema created successfully!';
END $$;
