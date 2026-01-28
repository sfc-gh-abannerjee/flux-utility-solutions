-- =============================================================================
-- 08_semantic_view.sql
-- Flux Utility Solutions - Cortex Analyst Semantic View Deployment
-- =============================================================================
-- Purpose: Deploy semantic view for natural language analytics
-- Dependencies: All PRODUCTION tables (01-07)
-- Jinja2 Variables:
--   <% database %>  - Target database name
--
-- Note: The semantic model YAML is in models/utility_semantic_model.yaml
-- This script creates the semantic view from inline YAML for portability
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE SCHEMA APPLICATIONS;

-- -----------------------------------------------------------------------------
-- 1. CREATE SEMANTIC VIEW
-- -----------------------------------------------------------------------------
-- Using CREATE OR ALTER for idempotent deployments

CREATE OR ALTER SEMANTIC VIEW UTILITY_SEMANTIC_VIEW
COMMENT = 'Flux Utility Solutions - 30-table semantic model for Cortex Analyst'
AS
$$
name: utility_semantic_view
description: |
  Comprehensive semantic model for utility grid analytics covering AMI readings,
  transformer health, customer profiles, and operational metrics.
  Optimized for summer peak analysis (July-August focus).

tables:
  # ===========================================================================
  # AMI DATA
  # ===========================================================================
  - name: AMI_READINGS_ENHANCED
    synonyms:
      - AMI_READINGS
      - INTERVAL_READINGS
      - METER_READINGS
      - ENERGY_DATA
    description: >
      Enhanced AMI readings with voltage sag events and outage tracking.
      7.1 billion rows at 15-minute intervals. July 2024 - August 2025.
    base_table:
      database: <% database %>
      schema: PRODUCTION
      table: AMI_READINGS_FINAL
    
    dimensions:
      - name: METER_ID
        synonyms: [meter, meter_number]
        description: Unique smart meter identifier
        expr: METER_ID
        data_type: VARCHAR
        sample_values: ['MTR-00000001', 'MTR-00000002', 'MTR-00000003']
      
      - name: SAG_TYPE
        description: Type of voltage sag event
        expr: SAG_TYPE
        data_type: VARCHAR
        sample_values: ['SEVERE_SAG', 'MODERATE_SAG', 'SWELL']
      
      - name: TIMESTAMP
        synonyms: [reading_time, time, date]
        description: 15-minute interval timestamp
        expr: TIMESTAMP
        data_type: TIMESTAMP_NTZ
    
    time_dimensions:
      - name: READING_DATE
        synonyms: [date, day]
        description: Date of reading
        expr: DATE_TRUNC('DAY', TIMESTAMP)
        data_type: DATE
      
      - name: READING_MONTH
        synonyms: [month]
        description: Month of reading
        expr: DATE_TRUNC('MONTH', TIMESTAMP)
        data_type: DATE
    
    facts:
      - name: USAGE_KWH
        synonyms: [consumption, energy_usage, kwh, kilowatt_hours]
        description: Energy consumption in kilowatt-hours for 15-minute interval
        expr: USAGE_KWH
        data_type: FLOAT
      
      - name: USAGE_KWH_ADJUSTED
        description: Usage adjusted to 0 during outages
        expr: USAGE_KWH_ADJUSTED
        data_type: FLOAT
      
      - name: VOLTAGE
        synonyms: [volts, voltage_reading]
        description: Voltage reading in volts
        expr: VOLTAGE
        data_type: NUMBER
      
      - name: POWER_FACTOR
        description: Power factor (0.80-1.00 typical)
        expr: POWER_FACTOR
        data_type: NUMBER
      
      - name: VOLTAGE_DROP_AMOUNT
        description: Voltage drop during sag events
        expr: VOLTAGE_DROP_AMOUNT
        data_type: NUMBER
    
    metrics:
      - name: TOTAL_CONSUMPTION
        synonyms: [total_kwh, total_usage]
        description: Total energy consumption in kWh
        expr: SUM(USAGE_KWH_ADJUSTED)
        data_type: NUMBER
      
      - name: AVG_CONSUMPTION
        synonyms: [average_kwh, avg_usage]
        description: Average energy consumption per interval
        expr: AVG(USAGE_KWH_ADJUSTED)
        data_type: NUMBER
      
      - name: ACTIVE_METER_COUNT
        description: Count of distinct meters reporting
        expr: COUNT(DISTINCT METER_ID)
        data_type: NUMBER
      
      - name: AVG_VOLTAGE
        description: Average voltage across readings
        expr: AVG(VOLTAGE)
        data_type: NUMBER
    
    filters:
      - name: SUMMER_2024
        description: July-August 2024 data
        expr: TIMESTAMP BETWEEN '2024-07-01' AND '2024-08-31'
      
      - name: SUMMER_2025
        description: July-August 2025 data
        expr: TIMESTAMP BETWEEN '2025-07-01' AND '2025-08-31'
      
      - name: LOW_VOLTAGE
        description: Readings below ANSI minimum (114V)
        expr: VOLTAGE < 114
      
      - name: VALID_READINGS
        description: Non-outage readings only
        expr: IS_OUTAGE = FALSE

  # ===========================================================================
  # CUSTOMERS
  # ===========================================================================
  - name: CUSTOMERS_MASTER_DATA
    synonyms:
      - CUSTOMERS
      - CUSTOMER_PROFILES
      - ACCOUNTS
    description: >
      Customer master data with 686,000 profiles including demographics,
      service addresses, and income segmentation.
    base_table:
      database: <% database %>
      schema: PRODUCTION
      table: CUSTOMERS_MASTER_DATA
    
    dimensions:
      - name: CUSTOMER_ID
        synonyms: [customer, account]
        description: Unique customer identifier
        expr: CUSTOMER_ID
        data_type: VARCHAR
        sample_values: ['CUST-00000001', 'CUST-00000002']
      
      - name: FULL_NAME
        synonyms: [name, customer_name]
        description: Customer full name
        expr: FULL_NAME
        data_type: VARCHAR
      
      - name: CITY
        description: Service city
        expr: CITY
        data_type: VARCHAR
        sample_values: ['Houston', 'Katy', 'Sugar Land', 'Galveston']
      
      - name: ZIP_CODE
        synonyms: [zip, postal_code]
        description: Service ZIP code
        expr: ZIP_CODE
        data_type: VARCHAR
      
      - name: CUSTOMER_SEGMENT
        synonyms: [segment, type]
        description: Customer type (RESIDENTIAL, COMMERCIAL, INDUSTRIAL)
        expr: CUSTOMER_SEGMENT
        data_type: VARCHAR
        sample_values: ['RESIDENTIAL', 'COMMERCIAL', 'INDUSTRIAL']
      
      - name: INCOME_SEGMENT
        description: Income bracket
        expr: INCOME_SEGMENT
        data_type: VARCHAR
        sample_values: ['LOW', 'LOWER_MIDDLE', 'MIDDLE', 'UPPER_MIDDLE', 'HIGH']
      
      - name: ACCOUNT_STATUS
        description: Account status
        expr: ACCOUNT_STATUS
        data_type: VARCHAR
        sample_values: ['ACTIVE', 'INACTIVE', 'SUSPENDED']
    
    metrics:
      - name: CUSTOMER_COUNT
        description: Total number of customers
        expr: COUNT(DISTINCT CUSTOMER_ID)
        data_type: NUMBER

  # ===========================================================================
  # TRANSFORMERS
  # ===========================================================================
  - name: TRANSFORMER_HOURLY_LOAD
    synonyms:
      - TRANSFORMER_LOADING
      - TRANSFORMER_LOAD
      - HOURLY_LOAD
    description: >
      Hourly transformer loading data with 211 million rows.
      Includes load factor, capacity utilization, and thermal stress.
    base_table:
      database: <% database %>
      schema: PRODUCTION
      table: TRANSFORMER_HOURLY_LOAD
    
    dimensions:
      - name: TRANSFORMER_ID
        synonyms: [transformer, xfmr]
        description: Transformer identifier
        expr: TRANSFORMER_ID
        data_type: VARCHAR
      
      - name: THERMAL_STRESS_CATEGORY
        synonyms: [stress_level, risk]
        description: Thermal stress category
        expr: THERMAL_STRESS_CATEGORY
        data_type: VARCHAR
        sample_values: ['LOW', 'MODERATE', 'HIGH', 'CRITICAL']
    
    time_dimensions:
      - name: LOAD_HOUR
        synonyms: [hour, timestamp]
        description: Hour of measurement
        expr: LOAD_HOUR
        data_type: TIMESTAMP_NTZ
    
    facts:
      - name: LOAD_KW
        synonyms: [load, power]
        description: Current load in kilowatts
        expr: LOAD_KW
        data_type: NUMBER
      
      - name: RATED_KVA
        synonyms: [capacity, rating]
        description: Rated transformer capacity in kVA
        expr: RATED_KVA
        data_type: NUMBER
      
      - name: LOAD_FACTOR_PCT
        synonyms: [utilization, loading_percent]
        description: Load as percentage of rated capacity
        expr: LOAD_FACTOR_PCT
        data_type: NUMBER
      
      - name: IS_OVERLOADED
        description: TRUE if load exceeds 100% capacity
        expr: IS_OVERLOADED
        data_type: BOOLEAN
    
    metrics:
      - name: AVG_LOAD_FACTOR
        description: Average load factor percentage
        expr: AVG(LOAD_FACTOR_PCT)
        data_type: NUMBER
      
      - name: PEAK_LOAD_FACTOR
        description: Maximum load factor percentage
        expr: MAX(LOAD_FACTOR_PCT)
        data_type: NUMBER
      
      - name: OVERLOAD_HOURS
        description: Count of hours with overloading
        expr: SUM(CASE WHEN IS_OVERLOADED THEN 1 ELSE 0 END)
        data_type: NUMBER
    
    filters:
      - name: OVERLOADED
        description: Transformers currently overloaded
        expr: IS_OVERLOADED = TRUE
      
      - name: HIGH_RISK
        description: High or critical thermal stress
        expr: THERMAL_STRESS_CATEGORY IN ('HIGH', 'CRITICAL')

  # ===========================================================================
  # TRANSFORMER METADATA
  # ===========================================================================
  - name: TRANSFORMER_METADATA
    synonyms:
      - TRANSFORMERS
      - TRANSFORMER_ASSETS
    description: >
      Transformer fleet metadata with 91,000 assets including specifications,
      location, health scores, and CIM-compliant topology.
    base_table:
      database: <% database %>
      schema: PRODUCTION
      table: TRANSFORMER_METADATA
    
    dimensions:
      - name: TRANSFORMER_ID
        description: Transformer identifier
        expr: TRANSFORMER_ID
        data_type: VARCHAR
      
      - name: SUBSTATION_ID
        description: Parent substation
        expr: SUBSTATION_ID
        data_type: VARCHAR
      
      - name: CIRCUIT_ID
        description: Circuit/feeder assignment
        expr: CIRCUIT_ID
        data_type: VARCHAR
      
      - name: TRANSFORMER_ROLE
        description: Transformer role (SERVICE, SPLIT, NETWORK)
        expr: TRANSFORMER_ROLE
        data_type: VARCHAR
        sample_values: ['SERVICE', 'SPLIT', 'NETWORK']
      
      - name: LOCATION_AREA
        description: Geographic area
        expr: LOCATION_AREA
        data_type: VARCHAR
        sample_values: ['Houston Metro', 'Coastal Texas', 'Harris County', 'Montgomery County']
    
    facts:
      - name: RATED_KVA
        description: Rated capacity in kVA
        expr: RATED_KVA
        data_type: NUMBER
      
      - name: AGE_YEARS
        description: Transformer age in years
        expr: AGE_YEARS
        data_type: NUMBER
      
      - name: HEALTH_SCORE
        description: Asset health score (0-100)
        expr: HEALTH_SCORE
        data_type: NUMBER
      
      - name: LOAD_UTILIZATION_PCT
        description: Current load utilization percentage
        expr: LOAD_UTILIZATION_PCT
        data_type: NUMBER
      
      - name: METER_COUNT
        description: Number of meters served
        expr: METER_COUNT
        data_type: NUMBER
    
    metrics:
      - name: TRANSFORMER_COUNT
        description: Total transformers
        expr: COUNT(*)
        data_type: NUMBER
      
      - name: AVG_AGE
        description: Average transformer age
        expr: AVG(AGE_YEARS)
        data_type: NUMBER
      
      - name: AVG_HEALTH_SCORE
        description: Average health score
        expr: AVG(HEALTH_SCORE)
        data_type: NUMBER

# ===========================================================================
# RELATIONSHIPS
# ===========================================================================
relationships:
  - name: meter_to_customer
    left_table: AMI_READINGS_ENHANCED
    right_table: CUSTOMERS_MASTER_DATA
    relationship_columns:
      - left_column: METER_ID
        right_column: PRIMARY_METER_ID
    join_type: many_to_one
    relationship_type: many_to_one
  
  - name: transformer_load_to_metadata
    left_table: TRANSFORMER_HOURLY_LOAD
    right_table: TRANSFORMER_METADATA
    relationship_columns:
      - left_column: TRANSFORMER_ID
        right_column: TRANSFORMER_ID
    join_type: many_to_one
    relationship_type: many_to_one

# ===========================================================================
# VERIFIED QUERIES
# ===========================================================================
verified_queries:
  - name: top_consumers_by_usage
    question: "Who are the top 10 customers by energy consumption?"
    verified_at: 2026-01-28
    verified_by: Cortex Code
    sql: |
      SELECT 
        c.FULL_NAME,
        c.CITY,
        c.CUSTOMER_SEGMENT,
        SUM(a.USAGE_KWH) as TOTAL_KWH
      FROM <% database %>.PRODUCTION.AMI_READINGS_FINAL a
      JOIN <% database %>.PRODUCTION.CUSTOMERS_MASTER_DATA c 
        ON a.METER_ID = c.PRIMARY_METER_ID
      GROUP BY 1, 2, 3
      ORDER BY TOTAL_KWH DESC
      LIMIT 10

  - name: high_risk_transformers
    question: "Which transformers are at risk of failure?"
    verified_at: 2026-01-28
    verified_by: Cortex Code
    sql: |
      SELECT 
        TRANSFORMER_ID,
        AVG(LOAD_FACTOR_PCT) as AVG_LOAD_PCT,
        MAX(LOAD_FACTOR_PCT) as PEAK_LOAD_PCT,
        SUM(CASE WHEN IS_OVERLOADED THEN 1 ELSE 0 END) as OVERLOAD_HOURS
      FROM <% database %>.PRODUCTION.TRANSFORMER_HOURLY_LOAD
      GROUP BY 1
      HAVING PEAK_LOAD_PCT > 110
      ORDER BY PEAK_LOAD_PCT DESC
      LIMIT 20

  - name: monthly_usage_trend
    question: "What is the monthly energy usage trend?"
    verified_at: 2026-01-28
    verified_by: Cortex Code
    sql: |
      SELECT 
        DATE_TRUNC('MONTH', TIMESTAMP) as MONTH,
        SUM(USAGE_KWH) as TOTAL_KWH,
        COUNT(DISTINCT METER_ID) as ACTIVE_METERS,
        AVG(USAGE_KWH) as AVG_INTERVAL_KWH
      FROM <% database %>.PRODUCTION.AMI_READINGS_FINAL
      GROUP BY 1
      ORDER BY 1
$$;

-- -----------------------------------------------------------------------------
-- 2. GRANT ACCESS TO USER ROLE
-- -----------------------------------------------------------------------------

GRANT SELECT ON SEMANTIC VIEW UTILITY_SEMANTIC_VIEW 
    TO ROLE IDENTIFIER('<% user_role %>');

-- -----------------------------------------------------------------------------
-- 3. VERIFY DEPLOYMENT
-- -----------------------------------------------------------------------------

SHOW SEMANTIC VIEWS IN SCHEMA APPLICATIONS;

-- Test semantic view (basic query)
SELECT * FROM TABLE(
    SNOWFLAKE.CORTEX.SEMANTIC_VIEW_COLUMNS('<% database %>.APPLICATIONS.UTILITY_SEMANTIC_VIEW')
) LIMIT 10;

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 09_cortex_search_services.sql to create search services
-- =============================================================================
