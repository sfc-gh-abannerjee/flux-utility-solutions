-- =============================================================================
-- 04_meters_infrastructure.sql
-- Flux Utility Solutions - Meter and Pole Infrastructure Tables
-- =============================================================================
-- Purpose: Create meter and pole infrastructure tables
-- Dependencies: 03_substations_transformers.sql
-- Jinja2 Variables:
--   <% database %>   - Target database name
--   <% warehouse %>  - Target warehouse name
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE WAREHOUSE IDENTIFIER('<% warehouse %>');
USE SCHEMA PRODUCTION;

-- -----------------------------------------------------------------------------
-- 1. GRID_POLES_INFRASTRUCTURE
-- -----------------------------------------------------------------------------
-- 62,000+ utility poles connecting transformers to meters
-- Naming convention: POLE-XXXXX

CREATE OR ALTER TABLE GRID_POLES_INFRASTRUCTURE (
    -- Primary key
    POLE_ID VARCHAR(30) NOT NULL PRIMARY KEY,
    
    -- External references
    OSM_POLE_ID NUMBER(18,0),  -- OpenStreetMap ID if sourced from OSM
    
    -- Topology
    TRANSFORMER_ID VARCHAR(50),
    SUBSTATION_ID VARCHAR(20),
    CIRCUIT_ID VARCHAR(20),
    
    -- Location
    LATITUDE FLOAT NOT NULL,
    LONGITUDE FLOAT NOT NULL,
    
    -- Physical attributes
    POLE_HEIGHT_FT NUMBER(10,0),
    POLE_MATERIAL VARCHAR(20),  -- WOOD, STEEL, CONCRETE, COMPOSITE
    POLE_CLASS VARCHAR(10),     -- 1, 2, 3, 4, 5 (ANSI classes)
    POLE_SOURCE VARCHAR(20),    -- OSM, SYNTHETIC, OVERTURE
    
    -- Equipment
    INSTALLED_EQUIPMENT_COUNT NUMBER(5,0),
    ATTACHMENT_COUNT NUMBER(5,0),
    
    -- Condition
    HEALTH_SCORE NUMBER(5,2),
    CONDITION_STATUS VARCHAR(10),  -- GOOD, FAIR, POOR, CRITICAL
    LOAD_UTILIZATION_PCT NUMBER(5,0),
    LAST_INSPECTION_DATE DATE,
    
    -- Audit
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (CIRCUIT_ID, TRANSFORMER_ID)
COMMENT = 'Utility pole infrastructure - 62,000 poles';

-- -----------------------------------------------------------------------------
-- 2. METER_INFRASTRUCTURE
-- -----------------------------------------------------------------------------
-- 597,000 smart meters with full topology assignments
-- Naming convention: MTR-XXXXXXXX

CREATE OR ALTER TABLE METER_INFRASTRUCTURE (
    -- Primary key
    METER_ID VARCHAR(20) NOT NULL PRIMARY KEY,
    
    -- Topology assignments
    TRANSFORMER_ID VARCHAR(50),
    POLE_ID VARCHAR(30),
    CIRCUIT_ID VARCHAR(20),
    SUBSTATION_ID VARCHAR(20),
    
    -- Location (meter)
    METER_LATITUDE FLOAT NOT NULL,
    METER_LONGITUDE FLOAT NOT NULL,
    LOCATION_COORDINATES VARCHAR(100),
    
    -- Location (associated pole)
    POLE_LATITUDE FLOAT,
    POLE_LONGITUDE FLOAT,
    POLE_TYPE VARCHAR(20),
    POLE_MATERIAL VARCHAR(20),
    POLE_HEIGHT_FT NUMBER(10,0),
    
    -- Geographic context
    CITY VARCHAR(100),
    ZIP_CODE VARCHAR(10),
    COUNTY_NAME VARCHAR(50),
    
    -- Meter attributes
    METER_TYPE VARCHAR(20),  -- RESIDENTIAL, COMMERCIAL, INDUSTRIAL
    COMMISSIONED_DATE DATE,
    CUSTOMER_SEGMENT_ID VARCHAR(20),
    CONDITION_STATUS VARCHAR(10),
    HEALTH_SCORE FLOAT,
    
    -- Building association
    BUILDING_ID VARCHAR(50),
    BUILDING_TYPE VARCHAR(50),
    PROPERTY_CATEGORY VARCHAR(50),
    ESTIMATED_SQFT NUMBER(10,0),
    DISTANCE_TO_BUILDING_METERS NUMBER(10,0),
    
    -- OSM snapping (geospatial accuracy)
    SNAPPED_TO_OSM_POLE_ID VARCHAR(50),
    OSM_POWER_TYPE VARCHAR(50),
    SNAP_DISTANCE_METERS FLOAT,
    ORIGINAL_SYNTHETIC_LAT FLOAT,
    ORIGINAL_SYNTHETIC_LON FLOAT,
    SNAPPED_AT TIMESTAMP_LTZ,
    
    -- Flags
    IS_OFFSHORE_FACILITY BOOLEAN DEFAULT FALSE,
    
    -- Audit
    LAST_UPDATED TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (TRANSFORMER_ID, CIRCUIT_ID, ZIP_CODE)
COMMENT = 'Smart meter infrastructure - 597,000 meters with topology assignments';

-- -----------------------------------------------------------------------------
-- 3. METER_BUILDING_MATCHES
-- -----------------------------------------------------------------------------
-- Association between meters and HCAD building footprints

CREATE OR ALTER TABLE METER_BUILDING_MATCHES (
    METER_ID VARCHAR(20) NOT NULL PRIMARY KEY,
    BUILDING_ID VARCHAR(50),
    MATCH_TYPE VARCHAR(20),  -- EXACT, NEAREST, INTERPOLATED
    DISTANCE_METERS NUMBER(10,2),
    BUILDING_SQFT NUMBER(10,0),
    BUILDING_TYPE VARCHAR(50),
    MATCH_CONFIDENCE NUMBER(3,2),
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Meter to building spatial matches';

-- -----------------------------------------------------------------------------
-- 4. VERIFICATION
-- -----------------------------------------------------------------------------

SELECT 'GRID_POLES_INFRASTRUCTURE' as table_name, COUNT(*) as row_count FROM GRID_POLES_INFRASTRUCTURE
UNION ALL
SELECT 'METER_INFRASTRUCTURE', COUNT(*) FROM METER_INFRASTRUCTURE
UNION ALL
SELECT 'METER_BUILDING_MATCHES', COUNT(*) FROM METER_BUILDING_MATCHES;

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 05_customers_master.sql to create customer tables
-- =============================================================================
