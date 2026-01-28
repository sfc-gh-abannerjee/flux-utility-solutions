-- =============================================================================
-- 12_postgres_instance.sql
-- Flux Utility Solutions - PostgreSQL Instance for Transactional Data
-- =============================================================================
-- Purpose: Create PostgreSQL database for real-time transactional workloads
-- Dependencies: 01_database_infrastructure.sql
-- Jinja2 Variables:
--   <% database %>          - Target database name
--   <% postgres_instance %> - PostgreSQL instance name
--   <% admin_role %>        - Admin role
--
-- Note: PostgreSQL provides <20ms latency for real-time operations
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');

-- -----------------------------------------------------------------------------
-- 1. CREATE POSTGRESQL INSTANCE
-- -----------------------------------------------------------------------------
-- PostgreSQL 17.7 instance for transactional workloads

CREATE POSTGRES DATABASE IF NOT EXISTS IDENTIFIER('<% postgres_instance %>')
    COMMENT = 'Flux Operations - Real-time transactional database for <20ms latency operations'
    AUTO_SUSPEND_MINS = 60
    INITIAL_WAREHOUSE_SIZE = 'MEDIUM';

-- -----------------------------------------------------------------------------
-- 2. CREATE POSTGRESQL SCHEMAS
-- -----------------------------------------------------------------------------
-- Execute against PostgreSQL instance

-- Note: PostgreSQL schema creation requires EXECUTE IMMEDIATE FROM
-- or direct PostgreSQL client connection

-- Schema: operations - Real-time grid operations
-- Schema: scada - SCADA telemetry data
-- Schema: work_orders - Field service management
-- Schema: sync - CDC staging tables

-- -----------------------------------------------------------------------------
-- 3. CREATE CORE TABLES (PostgreSQL DDL)
-- -----------------------------------------------------------------------------
-- These would be executed via PostgreSQL client or EXECUTE IMMEDIATE

/*
-- Real-time meter readings (last 24 hours)
CREATE TABLE IF NOT EXISTS operations.meter_readings_realtime (
    reading_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    meter_id VARCHAR(50) NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    usage_kwh NUMERIC(10,4),
    voltage NUMERIC(6,2),
    power_factor NUMERIC(4,3),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Partitioned by day for efficient queries
    CONSTRAINT meter_readings_pk PRIMARY KEY (meter_id, timestamp)
) PARTITION BY RANGE (timestamp);

-- SCADA telemetry
CREATE TABLE IF NOT EXISTS scada.telemetry (
    telemetry_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id VARCHAR(50) NOT NULL,
    measurement_type VARCHAR(50) NOT NULL,
    value NUMERIC(15,4),
    unit VARCHAR(20),
    quality_code VARCHAR(10),
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    received_at TIMESTAMPTZ DEFAULT NOW()
);

-- Work orders
CREATE TABLE IF NOT EXISTS work_orders.field_orders (
    order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number VARCHAR(20) UNIQUE NOT NULL,
    order_type VARCHAR(50) NOT NULL,
    priority VARCHAR(20) DEFAULT 'NORMAL',
    status VARCHAR(30) DEFAULT 'CREATED',
    assigned_crew VARCHAR(100),
    asset_id VARCHAR(50),
    asset_type VARCHAR(50),
    location_lat NUMERIC(10,7),
    location_lon NUMERIC(10,7),
    description TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    scheduled_start TIMESTAMPTZ,
    scheduled_end TIMESTAMPTZ,
    actual_start TIMESTAMPTZ,
    actual_end TIMESTAMPTZ
);

-- Crew assignments
CREATE TABLE IF NOT EXISTS work_orders.crew_assignments (
    assignment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    crew_id VARCHAR(50) NOT NULL,
    crew_name VARCHAR(100),
    order_id UUID REFERENCES work_orders.field_orders(order_id),
    assigned_at TIMESTAMPTZ DEFAULT NOW(),
    status VARCHAR(30) DEFAULT 'ASSIGNED'
);

-- Outage events (real-time tracking)
CREATE TABLE IF NOT EXISTS operations.outage_events (
    event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    outage_number VARCHAR(20) UNIQUE,
    circuit_id VARCHAR(50),
    substation_id VARCHAR(50),
    cause VARCHAR(100),
    status VARCHAR(30) DEFAULT 'ACTIVE',
    affected_customers INTEGER DEFAULT 0,
    start_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    estimated_restoration TIMESTAMPTZ,
    actual_restoration TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
*/

-- -----------------------------------------------------------------------------
-- 4. CREATE CDC SYNC CONFIGURATION
-- -----------------------------------------------------------------------------
-- Tables to track CDC synchronization status

CREATE TABLE IF NOT EXISTS PRODUCTION.POSTGRES_CDC_CONFIG (
    CONFIG_ID VARCHAR(50) DEFAULT UUID_STRING(),
    SOURCE_SCHEMA VARCHAR(100) NOT NULL,
    SOURCE_TABLE VARCHAR(100) NOT NULL,
    TARGET_SCHEMA VARCHAR(100) NOT NULL,
    TARGET_TABLE VARCHAR(100) NOT NULL,
    SYNC_DIRECTION VARCHAR(20) DEFAULT 'POSTGRES_TO_SNOWFLAKE',
    CDC_TYPE VARCHAR(20) DEFAULT 'INCREMENTAL',
    PRIMARY_KEY_COLUMNS VARCHAR(500),
    LAST_SYNC_TIMESTAMP TIMESTAMP_NTZ,
    LAST_SYNC_ROWS NUMBER(15,0),
    SYNC_FREQUENCY_MINUTES NUMBER(10,0) DEFAULT 15,
    IS_ACTIVE BOOLEAN DEFAULT TRUE,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    PRIMARY KEY (SOURCE_SCHEMA, SOURCE_TABLE)
)
COMMENT = 'CDC synchronization configuration for PostgreSQL to Snowflake';

-- Insert default CDC configurations
INSERT INTO PRODUCTION.POSTGRES_CDC_CONFIG (
    SOURCE_SCHEMA, SOURCE_TABLE, TARGET_SCHEMA, TARGET_TABLE,
    PRIMARY_KEY_COLUMNS, SYNC_FREQUENCY_MINUTES
) VALUES
    ('operations', 'meter_readings_realtime', 'PRODUCTION', 'AMI_READINGS_CDC_STAGING', 'meter_id,timestamp', 5),
    ('scada', 'telemetry', 'PRODUCTION', 'SCADA_TELEMETRY_CDC_STAGING', 'telemetry_id', 1),
    ('work_orders', 'field_orders', 'PRODUCTION', 'WORK_ORDERS_CDC_STAGING', 'order_id', 15),
    ('operations', 'outage_events', 'PRODUCTION', 'OUTAGE_EVENTS_CDC_STAGING', 'event_id', 1)
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- 5. CREATE CDC STAGING TABLES
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS PRODUCTION.AMI_READINGS_CDC_STAGING (
    READING_ID VARCHAR(50),
    METER_ID VARCHAR(50),
    TIMESTAMP TIMESTAMP_NTZ,
    USAGE_KWH FLOAT,
    VOLTAGE NUMBER(6,2),
    POWER_FACTOR NUMBER(4,3),
    CDC_OPERATION VARCHAR(10),  -- INSERT, UPDATE, DELETE
    CDC_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'CDC staging for real-time meter readings from PostgreSQL';

CREATE TABLE IF NOT EXISTS PRODUCTION.SCADA_TELEMETRY_CDC_STAGING (
    TELEMETRY_ID VARCHAR(50),
    DEVICE_ID VARCHAR(50),
    MEASUREMENT_TYPE VARCHAR(50),
    VALUE FLOAT,
    UNIT VARCHAR(20),
    QUALITY_CODE VARCHAR(10),
    TIMESTAMP TIMESTAMP_NTZ,
    CDC_OPERATION VARCHAR(10),
    CDC_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'CDC staging for SCADA telemetry from PostgreSQL';

CREATE TABLE IF NOT EXISTS PRODUCTION.WORK_ORDERS_CDC_STAGING (
    ORDER_ID VARCHAR(50),
    ORDER_NUMBER VARCHAR(20),
    ORDER_TYPE VARCHAR(50),
    PRIORITY VARCHAR(20),
    STATUS VARCHAR(30),
    ASSIGNED_CREW VARCHAR(100),
    ASSET_ID VARCHAR(50),
    ASSET_TYPE VARCHAR(50),
    DESCRIPTION TEXT,
    SCHEDULED_START TIMESTAMP_NTZ,
    SCHEDULED_END TIMESTAMP_NTZ,
    CDC_OPERATION VARCHAR(10),
    CDC_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'CDC staging for work orders from PostgreSQL';

CREATE TABLE IF NOT EXISTS PRODUCTION.OUTAGE_EVENTS_CDC_STAGING (
    EVENT_ID VARCHAR(50),
    OUTAGE_NUMBER VARCHAR(20),
    CIRCUIT_ID VARCHAR(50),
    SUBSTATION_ID VARCHAR(50),
    CAUSE VARCHAR(100),
    STATUS VARCHAR(30),
    AFFECTED_CUSTOMERS NUMBER(10,0),
    START_TIME TIMESTAMP_NTZ,
    ESTIMATED_RESTORATION TIMESTAMP_NTZ,
    ACTUAL_RESTORATION TIMESTAMP_NTZ,
    CDC_OPERATION VARCHAR(10),
    CDC_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'CDC staging for outage events from PostgreSQL';

-- -----------------------------------------------------------------------------
-- 6. CREATE CDC SYNC PROCEDURE
-- -----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE SYNC_POSTGRES_TO_SNOWFLAKE(
    P_SOURCE_SCHEMA VARCHAR,
    P_SOURCE_TABLE VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Synchronize data from PostgreSQL to Snowflake staging tables'
AS
$$
DECLARE
    v_config RECORD;
    v_rows_synced NUMBER;
BEGIN
    -- Get sync configuration
    SELECT * INTO v_config
    FROM PRODUCTION.POSTGRES_CDC_CONFIG
    WHERE SOURCE_SCHEMA = :P_SOURCE_SCHEMA
      AND SOURCE_TABLE = :P_SOURCE_TABLE
      AND IS_ACTIVE = TRUE;
    
    IF (v_config IS NULL) THEN
        RETURN 'No active sync configuration found';
    END IF;
    
    -- Note: Actual CDC implementation would use Snowflake's PostgreSQL connector
    -- or external tools like Debezium, Airbyte, or Fivetran
    
    -- Update sync timestamp
    UPDATE PRODUCTION.POSTGRES_CDC_CONFIG
    SET LAST_SYNC_TIMESTAMP = CURRENT_TIMESTAMP(),
        UPDATED_AT = CURRENT_TIMESTAMP()
    WHERE SOURCE_SCHEMA = :P_SOURCE_SCHEMA
      AND SOURCE_TABLE = :P_SOURCE_TABLE;
    
    RETURN 'Sync completed for ' || :P_SOURCE_SCHEMA || '.' || :P_SOURCE_TABLE;
END;
$$;

-- -----------------------------------------------------------------------------
-- 7. GRANTS
-- -----------------------------------------------------------------------------

GRANT USAGE ON DATABASE IDENTIFIER('<% postgres_instance %>') TO ROLE IDENTIFIER('<% admin_role %>');
GRANT SELECT ON ALL TABLES IN SCHEMA PRODUCTION TO ROLE IDENTIFIER('<% user_role %>');

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 13_spcs_compute.sql for Snowpark Container Services
-- =============================================================================
