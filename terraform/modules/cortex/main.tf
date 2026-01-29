# =============================================================================
# Cortex Module - Main Configuration
# =============================================================================
# Supports:
#   - Semantic Views (snowflake_semantic_view resource - preview)
#   - Compute Pools (via snowflake_execute)
#   - Network Rules (via snowflake_execute)
#   - SPCS Stages
# 
# Note: Cortex Search Services and Agents still require SQL scripts.
# =============================================================================

terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = ">= 2.11.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Image Repository (for SPCS)
# -----------------------------------------------------------------------------

resource "snowflake_stage" "spcs_specs" {
  count = var.create_image_repository ? 1 : 0
  
  database = var.database_name
  schema   = "APPLICATIONS"
  name     = "SPCS_SPECS"
  
  directory = "ENABLE = TRUE"
  comment   = "Stage for SPCS service specification files"
}

# -----------------------------------------------------------------------------
# Compute Pool (for SPCS)
# Note: Compute pools require snowflake_unsafe_execute or SQL scripts
# -----------------------------------------------------------------------------

# Compute pool creation requires execute as it's not natively supported
resource "snowflake_execute" "compute_pool" {
  count = var.compute_pool_config != null ? 1 : 0
  
  execute = <<-SQL
    CREATE COMPUTE POOL IF NOT EXISTS ${var.compute_pool_config.name}
      MIN_NODES = ${var.compute_pool_config.min_nodes}
      MAX_NODES = ${var.compute_pool_config.max_nodes}
      INSTANCE_FAMILY = ${var.compute_pool_config.instance_family}
      AUTO_SUSPEND_SECS = ${var.compute_pool_config.auto_suspend_secs}
      AUTO_RESUME = TRUE
      COMMENT = 'Flux compute pool managed by Terraform';
  SQL
  
  revert = <<-SQL
    DROP COMPUTE POOL IF EXISTS ${var.compute_pool_config.name};
  SQL
}

# -----------------------------------------------------------------------------
# Network Rules (for external access)
# -----------------------------------------------------------------------------

resource "snowflake_execute" "external_access_rule" {
  count = var.create_image_repository ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE NETWORK RULE ${var.database_name}.APPLICATIONS.FLUX_EXTERNAL_ACCESS_RULE
      TYPE = HOST_PORT
      MODE = EGRESS
      VALUE_LIST = ('api.weather.gov:443', 'nominatim.openstreetmap.org:443')
      COMMENT = 'External network access for Flux services';
  SQL
  
  revert = <<-SQL
    DROP NETWORK RULE IF EXISTS ${var.database_name}.APPLICATIONS.FLUX_EXTERNAL_ACCESS_RULE;
  SQL
}

# -----------------------------------------------------------------------------
# Semantic View (snowflake_semantic_view resource - PREVIEW)
# Reference: https://www.snowflake.com/en/engineering-blog/semantic-view-terraform-provider/
# -----------------------------------------------------------------------------

resource "snowflake_semantic_view" "utility_semantic_view" {
  count = var.create_semantic_view ? 1 : 0

  database = var.database_name
  schema   = "APPLICATIONS"
  name     = var.semantic_view_name
  comment  = "Utility grid analytics semantic model for AMI readings, transformer health, and customer profiles."

  # AMI Readings table
  tables {
    table_alias = "ami"
    table_name  = "${var.database_name}.PRODUCTION.AMI_READINGS_FINAL"
    comment     = "AMI meter readings with 15-minute interval data"
    synonym     = ["meter readings", "interval data", "energy data"]
  }

  # Customers table
  tables {
    table_alias = "customers"
    table_name  = "${var.database_name}.PRODUCTION.CUSTOMERS_MASTER_DATA"
    primary_key = ["CUSTOMER_ID"]
    unique {
      values = ["PRIMARY_METER_ID"]
    }
    comment = "Customer profiles and account information"
    synonym = ["customer profiles", "accounts"]
  }

  # Transformer hourly load
  tables {
    table_alias = "xfmr_load"
    table_name  = "${var.database_name}.PRODUCTION.TRANSFORMER_HOURLY_LOAD"
    comment     = "Hourly transformer loading data"
    synonym     = ["transformer loading", "hourly load"]
  }

  # Transformer metadata
  tables {
    table_alias = "xfmr"
    table_name  = "${var.database_name}.PRODUCTION.TRANSFORMER_METADATA"
    primary_key = ["TRANSFORMER_ID"]
    comment     = "Transformer asset metadata"
    synonym     = ["transformers", "transformer assets"]
  }

  # Relationships
  relationships {
    relationship_identifier = "ami_to_customers"
    table_name_or_alias {
      table_alias = "ami"
    }
    relationship_columns = ["METER_ID"]
    referenced_table_name_or_alias {
      table_alias = "customers"
    }
    referenced_relationship_columns = ["PRIMARY_METER_ID"]
  }

  relationships {
    relationship_identifier = "xfmr_load_to_xfmr"
    table_name_or_alias {
      table_alias = "xfmr_load"
    }
    relationship_columns = ["TRANSFORMER_ID"]
    referenced_table_name_or_alias {
      table_alias = "xfmr"
    }
    referenced_relationship_columns = ["TRANSFORMER_ID"]
  }

  # Facts
  facts {
    qualified_expression_name = "ami.USAGE_KWH"
    sql_expression            = "ami.USAGE_KWH"
    comment                   = "Energy consumption in kilowatt-hours"
    synonym                   = ["consumption", "energy usage", "kwh"]
  }

  facts {
    qualified_expression_name = "ami.VOLTAGE"
    sql_expression            = "ami.VOLTAGE"
    comment                   = "Voltage reading in volts"
    synonym                   = ["volts", "voltage reading"]
  }

  facts {
    qualified_expression_name = "xfmr_load.LOAD_KW"
    sql_expression            = "xfmr_load.LOAD_KW"
    comment                   = "Current load in kilowatts"
    synonym                   = ["load", "power"]
  }

  facts {
    qualified_expression_name = "xfmr_load.LOAD_FACTOR_PCT"
    sql_expression            = "xfmr_load.LOAD_FACTOR_PCT"
    comment                   = "Load as percentage of rated capacity"
    synonym                   = ["utilization", "loading percent"]
  }

  facts {
    qualified_expression_name = "xfmr.HEALTH_SCORE"
    sql_expression            = "xfmr.HEALTH_SCORE"
    comment                   = "Asset health score 0-100"
  }

  facts {
    qualified_expression_name = "xfmr.AGE_YEARS"
    sql_expression            = "xfmr.AGE_YEARS"
    comment                   = "Transformer age in years"
  }

  facts {
    qualified_expression_name = "xfmr.RATED_KVA"
    sql_expression            = "xfmr.RATED_KVA"
    comment                   = "Rated capacity in kVA"
    synonym                   = ["capacity", "rating"]
  }

  # Dimensions
  dimensions {
    qualified_expression_name = "ami.METER_ID"
    sql_expression            = "ami.METER_ID"
    comment                   = "Unique smart meter identifier"
    synonym                   = ["meter", "meter number"]
  }

  dimensions {
    qualified_expression_name = "ami.TIMESTAMP"
    sql_expression            = "ami.TIMESTAMP"
    comment                   = "15-minute interval timestamp"
    synonym                   = ["reading time", "time", "date"]
  }

  dimensions {
    qualified_expression_name = "customers.CUSTOMER_ID"
    sql_expression            = "customers.CUSTOMER_ID"
    comment                   = "Unique customer identifier"
    synonym                   = ["customer", "account"]
  }

  dimensions {
    qualified_expression_name = "customers.FULL_NAME"
    sql_expression            = "customers.FULL_NAME"
    comment                   = "Customer full name"
    synonym                   = ["name", "customer name"]
  }

  dimensions {
    qualified_expression_name = "customers.CITY"
    sql_expression            = "customers.CITY"
    comment                   = "Service city"
  }

  dimensions {
    qualified_expression_name = "customers.ZIP_CODE"
    sql_expression            = "customers.ZIP_CODE"
    comment                   = "Service ZIP code"
    synonym                   = ["zip", "postal code"]
  }

  dimensions {
    qualified_expression_name = "customers.CUSTOMER_SEGMENT"
    sql_expression            = "customers.CUSTOMER_SEGMENT"
    comment                   = "Customer type (RESIDENTIAL, COMMERCIAL, INDUSTRIAL)"
    synonym                   = ["segment", "type"]
  }

  dimensions {
    qualified_expression_name = "xfmr.TRANSFORMER_ID"
    sql_expression            = "xfmr.TRANSFORMER_ID"
    comment                   = "Transformer identifier"
    synonym                   = ["transformer", "xfmr"]
  }

  dimensions {
    qualified_expression_name = "xfmr.LOCATION_AREA"
    sql_expression            = "xfmr.LOCATION_AREA"
    comment                   = "Geographic area"
  }

  dimensions {
    qualified_expression_name = "xfmr.SUBSTATION_ID"
    sql_expression            = "xfmr.SUBSTATION_ID"
    comment                   = "Parent substation"
  }

  dimensions {
    qualified_expression_name = "xfmr.CIRCUIT_ID"
    sql_expression            = "xfmr.CIRCUIT_ID"
    comment                   = "Circuit/feeder assignment"
  }

  dimensions {
    qualified_expression_name = "xfmr_load.THERMAL_STRESS_CATEGORY"
    sql_expression            = "xfmr_load.THERMAL_STRESS_CATEGORY"
    comment                   = "Thermal stress category (LOW, MODERATE, HIGH, CRITICAL)"
    synonym                   = ["stress level", "thermal risk"]
  }

  dimensions {
    qualified_expression_name = "xfmr_load.LOAD_HOUR"
    sql_expression            = "xfmr_load.LOAD_HOUR"
    comment                   = "Hour of measurement"
    synonym                   = ["hour"]
  }

  # Metrics
  metrics {
    semantic_expression {
      qualified_expression_name = "ami.TOTAL_CONSUMPTION"
      sql_expression            = "SUM(ami.USAGE_KWH)"
      comment                   = "Total energy consumption in kWh"
      synonym                   = ["total kwh", "total usage"]
    }
  }

  metrics {
    semantic_expression {
      qualified_expression_name = "ami.AVG_CONSUMPTION"
      sql_expression            = "AVG(ami.USAGE_KWH)"
      comment                   = "Average energy consumption per interval"
      synonym                   = ["average kwh", "avg usage"]
    }
  }

  metrics {
    semantic_expression {
      qualified_expression_name = "ami.METER_COUNT"
      sql_expression            = "COUNT(DISTINCT ami.METER_ID)"
      comment                   = "Count of distinct meters reporting"
    }
  }

  metrics {
    semantic_expression {
      qualified_expression_name = "ami.AVG_VOLTAGE"
      sql_expression            = "AVG(ami.VOLTAGE)"
      comment                   = "Average voltage across readings"
    }
  }

  metrics {
    semantic_expression {
      qualified_expression_name = "customers.CUSTOMER_COUNT"
      sql_expression            = "COUNT(DISTINCT customers.CUSTOMER_ID)"
      comment                   = "Total number of customers"
    }
  }

  metrics {
    semantic_expression {
      qualified_expression_name = "xfmr.TRANSFORMER_COUNT"
      sql_expression            = "COUNT(DISTINCT xfmr.TRANSFORMER_ID)"
      comment                   = "Total transformers"
    }
  }

  metrics {
    semantic_expression {
      qualified_expression_name = "xfmr.AVG_AGE"
      sql_expression            = "AVG(xfmr.AGE_YEARS)"
      comment                   = "Average transformer age"
    }
  }

  metrics {
    semantic_expression {
      qualified_expression_name = "xfmr.AVG_HEALTH_SCORE"
      sql_expression            = "AVG(xfmr.HEALTH_SCORE)"
      comment                   = "Average health score"
    }
  }

  metrics {
    semantic_expression {
      qualified_expression_name = "xfmr_load.AVG_LOAD_FACTOR"
      sql_expression            = "AVG(xfmr_load.LOAD_FACTOR_PCT)"
      comment                   = "Average load factor percentage"
    }
  }

  metrics {
    semantic_expression {
      qualified_expression_name = "xfmr_load.PEAK_LOAD_FACTOR"
      sql_expression            = "MAX(xfmr_load.LOAD_FACTOR_PCT)"
      comment                   = "Maximum load factor percentage"
    }
  }
}

# Grant SELECT on semantic view
resource "snowflake_grant_privileges_to_account_role" "semantic_view_grant" {
  count = var.create_semantic_view ? 1 : 0

  account_role_name = var.user_role
  privileges        = ["SELECT"]

  on_schema_object {
    object_type = "SEMANTIC VIEW"
    object_name = "${var.database_name}.APPLICATIONS.${var.semantic_view_name}"
  }

  depends_on = [snowflake_semantic_view.utility_semantic_view]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "stage_name" {
  description = "SPCS specs stage name"
  value       = var.create_image_repository ? snowflake_stage.spcs_specs[0].name : null
}

output "compute_pool_name" {
  description = "Compute pool name"
  value       = var.compute_pool_config != null ? var.compute_pool_config.name : null
}

output "cortex_note" {
  description = "Important note about Cortex components"
  value       = "Cortex Agents must be deployed via SQL scripts. Semantic Views can be deployed via Terraform (snowflake_semantic_view resource)."
}

output "semantic_view_name" {
  description = "Semantic view name"
  value       = var.create_semantic_view ? snowflake_semantic_view.utility_semantic_view[0].name : null
}
