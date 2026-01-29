# =============================================================================
# PostgreSQL Module - Managed PostgreSQL Service
# =============================================================================
# Creates PostgreSQL Managed Service instance for transactional workloads
# Enables <20ms OLTP queries in the 4-layer hybrid architecture
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
# PostgreSQL Managed Service Instance
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "postgres_instance" {
  execute = <<-SQL
    CREATE DATABASE IF NOT EXISTS ${var.postgres_database_name}
      FROM POSTGRESQL
      AUTO_RESUME = TRUE
      INSTANCE_SIZE = '${var.instance_size}'
      COMMENT = '${var.comment}';
  SQL
  
  revert = "DROP DATABASE IF EXISTS ${var.postgres_database_name};"
}

# -----------------------------------------------------------------------------
# PostgreSQL Schemas
# Note: Postgres schemas are managed differently than Snowflake schemas
# These are created via psycopg2 or similar from SPCS
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "postgres_operations_schema" {
  execute = <<-SQL
    -- Schema creation happens via PostgreSQL client
    -- This is a placeholder for tracking the expected schema structure
    SELECT 'PostgreSQL schema: operations' AS schema_note;
  SQL
  
  revert = "SELECT 'PostgreSQL schema drop: operations' AS schema_note;"
  
  depends_on = [snowflake_unsafe_execute.postgres_instance]
}

# -----------------------------------------------------------------------------
# External Access Integration for PostgreSQL
# Allows SPCS services to connect to PostgreSQL
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "postgres_network_rule" {
  count = var.create_external_access ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE NETWORK RULE ${var.snowflake_database}.${var.snowflake_schema}.POSTGRES_EGRESS_RULE
      TYPE = HOST_PORT
      MODE = EGRESS
      VALUE_LIST = ('${var.postgres_host}:5432')
      COMMENT = 'Network rule for PostgreSQL connectivity from SPCS';
  SQL
  
  revert = "DROP NETWORK RULE IF EXISTS ${var.snowflake_database}.${var.snowflake_schema}.POSTGRES_EGRESS_RULE;"
  
  depends_on = [snowflake_unsafe_execute.postgres_instance]
}

resource "snowflake_unsafe_execute" "postgres_secret" {
  count = var.create_external_access ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE SECRET ${var.snowflake_database}.${var.secrets_schema}.POSTGRES_CREDENTIALS
      TYPE = PASSWORD
      USERNAME = '${var.postgres_username}'
      PASSWORD = '${var.postgres_password}'
      COMMENT = 'PostgreSQL credentials for SPCS connectivity';
  SQL
  
  revert = "DROP SECRET IF EXISTS ${var.snowflake_database}.${var.secrets_schema}.POSTGRES_CREDENTIALS;"
}

resource "snowflake_unsafe_execute" "postgres_eai" {
  count = var.create_external_access ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION ${var.eai_name}
      ALLOWED_NETWORK_RULES = (${var.snowflake_database}.${var.snowflake_schema}.POSTGRES_EGRESS_RULE)
      ALLOWED_AUTHENTICATION_SECRETS = (${var.snowflake_database}.${var.secrets_schema}.POSTGRES_CREDENTIALS)
      ENABLED = TRUE
      COMMENT = 'External Access Integration for PostgreSQL from SPCS and UDFs';
  SQL
  
  revert = "DROP EXTERNAL ACCESS INTEGRATION IF EXISTS ${var.eai_name};"
  
  depends_on = [
    snowflake_unsafe_execute.postgres_network_rule,
    snowflake_unsafe_execute.postgres_secret
  ]
}

# -----------------------------------------------------------------------------
# CDC Pipeline Infrastructure
# Streams and tasks for Snowflake → PostgreSQL sync
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "cdc_stream" {
  count = var.create_cdc_pipeline ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE STREAM ${var.snowflake_database}.${var.snowflake_schema}.TRANSFORMER_CDC_STREAM
      ON TABLE ${var.snowflake_database}.PRODUCTION.TRANSFORMERS
      APPEND_ONLY = FALSE
      SHOW_INITIAL_ROWS = FALSE
      COMMENT = 'CDC stream for transformer changes to sync to PostgreSQL';
  SQL
  
  revert = "DROP STREAM IF EXISTS ${var.snowflake_database}.${var.snowflake_schema}.TRANSFORMER_CDC_STREAM;"
}

resource "snowflake_unsafe_execute" "cdc_task" {
  count = var.create_cdc_pipeline ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE TASK ${var.snowflake_database}.${var.snowflake_schema}.POSTGRES_SYNC_TASK
      WAREHOUSE = ${var.warehouse}
      SCHEDULE = '${var.cdc_schedule}'
      COMMENT = 'Syncs transformer changes to PostgreSQL for OLTP queries'
      WHEN SYSTEM$STREAM_HAS_DATA('${var.snowflake_database}.${var.snowflake_schema}.TRANSFORMER_CDC_STREAM')
    AS
      CALL ${var.snowflake_database}.${var.snowflake_schema}.SYNC_TRANSFORMERS_TO_POSTGRES();
  SQL
  
  revert = "DROP TASK IF EXISTS ${var.snowflake_database}.${var.snowflake_schema}.POSTGRES_SYNC_TASK;"
  
  depends_on = [snowflake_unsafe_execute.cdc_stream]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "postgres_instance" {
  description = "PostgreSQL instance details"
  value = {
    database_name = var.postgres_database_name
    instance_size = var.instance_size
    host          = var.postgres_host
  }
}

output "external_access_integration" {
  description = "External Access Integration name"
  value       = var.create_external_access ? var.eai_name : null
}

output "cdc_pipeline" {
  description = "CDC pipeline components"
  value = var.create_cdc_pipeline ? {
    stream = "${var.snowflake_database}.${var.snowflake_schema}.TRANSFORMER_CDC_STREAM"
    task   = "${var.snowflake_database}.${var.snowflake_schema}.POSTGRES_SYNC_TASK"
  } : null
}

output "connection_string_template" {
  description = "Template for PostgreSQL connection string"
  value       = "postgresql://<user>:<password>@${var.postgres_host}:5432/${var.postgres_database_name}"
  sensitive   = false
}
