# =============================================================================
# Cortex Module - Main Configuration
# =============================================================================
# Note: Cortex Search Services, Agents, and Semantic Views are not yet
# supported by the Terraform provider. Use SQL scripts for these components.
# =============================================================================

terraform {
  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.87"
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

# Compute pool creation requires unsafe_execute as it's not natively supported
resource "snowflake_unsafe_execute" "compute_pool" {
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

resource "snowflake_unsafe_execute" "external_access_rule" {
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
  value       = "Cortex Search Services, Agents, and Semantic Views must be deployed via SQL scripts (not Terraform)"
}
