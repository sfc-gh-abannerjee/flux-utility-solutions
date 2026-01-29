# =============================================================================
# Tables Module - Core Data Tables
# =============================================================================
# Creates the foundational tables for Flux Utility Solutions
# Uses unsafe_execute for dynamic table definitions
# =============================================================================

terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 0.87"
    }
  }
}

# -----------------------------------------------------------------------------
# Core Dimension Tables
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "substations_table" {
  execute = <<-SQL
    CREATE TABLE IF NOT EXISTS ${var.database_name}.${var.schema_name}.SUBSTATIONS (
      SUBSTATION_ID VARCHAR(50) PRIMARY KEY,
      SUBSTATION_NAME VARCHAR(200),
      LATITUDE FLOAT,
      LONGITUDE FLOAT,
      H3_INDEX VARCHAR(20),
      VOLTAGE_CLASS VARCHAR(50),
      CAPACITY_MW FLOAT,
      INSTALLATION_DATE DATE,
      STATUS VARCHAR(20) DEFAULT 'ACTIVE',
      REGION VARCHAR(100),
      CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
      UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    )
    CLUSTER BY (REGION, STATUS)
    COMMENT = 'Substation dimension table - 275 substations';
  SQL
  
  revert = "DROP TABLE IF EXISTS ${var.database_name}.${var.schema_name}.SUBSTATIONS;"
}

resource "snowflake_unsafe_execute" "transformers_table" {
  execute = <<-SQL
    CREATE TABLE IF NOT EXISTS ${var.database_name}.${var.schema_name}.TRANSFORMERS (
      TRANSFORMER_ID VARCHAR(50) PRIMARY KEY,
      SUBSTATION_ID VARCHAR(50) REFERENCES ${var.database_name}.${var.schema_name}.SUBSTATIONS(SUBSTATION_ID),
      TRANSFORMER_NAME VARCHAR(200),
      LATITUDE FLOAT,
      LONGITUDE FLOAT,
      H3_INDEX VARCHAR(20),
      MANUFACTURER VARCHAR(100),
      MODEL VARCHAR(100),
      RATED_CAPACITY_KVA FLOAT,
      INSTALLATION_DATE DATE,
      LAST_MAINTENANCE_DATE DATE,
      STATUS VARCHAR(20) DEFAULT 'ACTIVE',
      RISK_SCORE FLOAT,
      CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
      UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    )
    CLUSTER BY (SUBSTATION_ID, STATUS)
    COMMENT = 'Transformer dimension table - 91K transformers';
  SQL
  
  revert = "DROP TABLE IF EXISTS ${var.database_name}.${var.schema_name}.TRANSFORMERS;"
  
  depends_on = [snowflake_unsafe_execute.substations_table]
}

resource "snowflake_unsafe_execute" "meters_table" {
  execute = <<-SQL
    CREATE TABLE IF NOT EXISTS ${var.database_name}.${var.schema_name}.METERS (
      METER_ID VARCHAR(50) PRIMARY KEY,
      TRANSFORMER_ID VARCHAR(50) REFERENCES ${var.database_name}.${var.schema_name}.TRANSFORMERS(TRANSFORMER_ID),
      CUSTOMER_ID VARCHAR(50),
      METER_TYPE VARCHAR(50),
      LATITUDE FLOAT,
      LONGITUDE FLOAT,
      H3_INDEX VARCHAR(20),
      INSTALLATION_DATE DATE,
      STATUS VARCHAR(20) DEFAULT 'ACTIVE',
      CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
      UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    )
    CLUSTER BY (TRANSFORMER_ID, STATUS)
    COMMENT = 'Meter dimension table - 597K meters';
  SQL
  
  revert = "DROP TABLE IF EXISTS ${var.database_name}.${var.schema_name}.METERS;"
  
  depends_on = [snowflake_unsafe_execute.transformers_table]
}

resource "snowflake_unsafe_execute" "customers_table" {
  execute = <<-SQL
    CREATE TABLE IF NOT EXISTS ${var.database_name}.${var.schema_name}.CUSTOMERS (
      CUSTOMER_ID VARCHAR(50) PRIMARY KEY,
      CUSTOMER_NAME VARCHAR(200),
      CUSTOMER_TYPE VARCHAR(50),
      ADDRESS VARCHAR(500),
      CITY VARCHAR(100),
      STATE VARCHAR(50),
      ZIP_CODE VARCHAR(20),
      LATITUDE FLOAT,
      LONGITUDE FLOAT,
      H3_INDEX VARCHAR(20),
      ACCOUNT_STATUS VARCHAR(20) DEFAULT 'ACTIVE',
      SERVICE_START_DATE DATE,
      CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
      UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    )
    CLUSTER BY (CUSTOMER_TYPE, ACCOUNT_STATUS)
    COMMENT = 'Customer dimension table - 686K customers';
  SQL
  
  revert = "DROP TABLE IF EXISTS ${var.database_name}.${var.schema_name}.CUSTOMERS;"
}

# -----------------------------------------------------------------------------
# Core Fact Tables  
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "ami_readings_table" {
  execute = <<-SQL
    CREATE TABLE IF NOT EXISTS ${var.database_name}.${var.schema_name}.AMI_READINGS (
      READING_ID VARCHAR(50),
      METER_ID VARCHAR(50),
      READING_TIMESTAMP TIMESTAMP_NTZ,
      KWH_USAGE FLOAT,
      VOLTAGE FLOAT,
      CURRENT_AMPS FLOAT,
      POWER_FACTOR FLOAT,
      TEMPERATURE_F FLOAT,
      QUALITY_FLAG VARCHAR(10),
      CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    )
    CLUSTER BY (READING_TIMESTAMP, METER_ID)
    COMMENT = 'AMI readings fact table - 7.1B rows at scale';
  SQL
  
  revert = "DROP TABLE IF EXISTS ${var.database_name}.${var.schema_name}.AMI_READINGS;"
}

resource "snowflake_unsafe_execute" "transformer_hourly_table" {
  execute = <<-SQL
    CREATE TABLE IF NOT EXISTS ${var.database_name}.${var.schema_name}.TRANSFORMER_HOURLY_METRICS (
      TRANSFORMER_ID VARCHAR(50),
      HOUR_TIMESTAMP TIMESTAMP_NTZ,
      AVG_LOAD_PERCENT FLOAT,
      MAX_LOAD_PERCENT FLOAT,
      AVG_TEMPERATURE FLOAT,
      MAX_TEMPERATURE FLOAT,
      TOTAL_KWH FLOAT,
      METER_COUNT INTEGER,
      ALERT_COUNT INTEGER,
      CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    )
    CLUSTER BY (HOUR_TIMESTAMP, TRANSFORMER_ID)
    COMMENT = 'Transformer hourly aggregations - 211M rows';
  SQL
  
  revert = "DROP TABLE IF EXISTS ${var.database_name}.${var.schema_name}.TRANSFORMER_HOURLY_METRICS;"
}

resource "snowflake_unsafe_execute" "outage_events_table" {
  execute = <<-SQL
    CREATE TABLE IF NOT EXISTS ${var.database_name}.${var.schema_name}.OUTAGE_EVENTS (
      OUTAGE_ID VARCHAR(50) PRIMARY KEY,
      ASSET_TYPE VARCHAR(50),
      ASSET_ID VARCHAR(50),
      START_TIMESTAMP TIMESTAMP_NTZ,
      END_TIMESTAMP TIMESTAMP_NTZ,
      DURATION_MINUTES INTEGER,
      CAUSE VARCHAR(200),
      CUSTOMERS_AFFECTED INTEGER,
      RESTORATION_CREW VARCHAR(100),
      WEATHER_CONDITION VARCHAR(100),
      CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    )
    CLUSTER BY (START_TIMESTAMP, ASSET_TYPE)
    COMMENT = 'Outage events for reliability analysis';
  SQL
  
  revert = "DROP TABLE IF EXISTS ${var.database_name}.${var.schema_name}.OUTAGE_EVENTS;"
}

# -----------------------------------------------------------------------------
# Streaming Target Tables
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "streaming_ami_table" {
  count = var.create_streaming_tables ? 1 : 0
  
  execute = <<-SQL
    CREATE TABLE IF NOT EXISTS ${var.database_name}.${var.schema_name}.STREAMING_AMI_READINGS (
      METER_ID VARCHAR(50),
      READING_TIMESTAMP TIMESTAMP_NTZ,
      KWH_USAGE FLOAT,
      VOLTAGE FLOAT,
      CURRENT_AMPS FLOAT,
      POWER_FACTOR FLOAT,
      TEMPERATURE_F FLOAT,
      QUALITY_FLAG VARCHAR(10),
      INGESTION_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
      SOURCE VARCHAR(50) DEFAULT 'SNOWPIPE_STREAMING'
    )
    COMMENT = 'Real-time streaming AMI data from Flux Data Forge';
  SQL
  
  revert = "DROP TABLE IF EXISTS ${var.database_name}.${var.schema_name}.STREAMING_AMI_READINGS;"
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "tables_created" {
  description = "List of tables created"
  value = [
    "SUBSTATIONS",
    "TRANSFORMERS", 
    "METERS",
    "CUSTOMERS",
    "AMI_READINGS",
    "TRANSFORMER_HOURLY_METRICS",
    "OUTAGE_EVENTS"
  ]
}

output "fact_tables" {
  description = "Fact tables for analytics"
  value = ["AMI_READINGS", "TRANSFORMER_HOURLY_METRICS", "OUTAGE_EVENTS"]
}

output "dimension_tables" {
  description = "Dimension tables"
  value = ["SUBSTATIONS", "TRANSFORMERS", "METERS", "CUSTOMERS"]
}
