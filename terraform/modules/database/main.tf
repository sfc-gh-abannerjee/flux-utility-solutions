# =============================================================================
# Database Module - Main Configuration
# =============================================================================

terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = ">= 0.92"
    }
  }
}

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------

resource "snowflake_database" "flux" {
  name                        = var.database_name
  comment                     = "Flux Utility Solutions - Grid Analytics Platform"
  data_retention_time_in_days = var.data_retention_days
}

# -----------------------------------------------------------------------------
# Schemas
# -----------------------------------------------------------------------------

resource "snowflake_schema" "schemas" {
  for_each = toset(var.schemas)
  
  database = snowflake_database.flux.name
  name     = each.value
  
  comment = lookup(var.schema_comments, each.value, "Schema for ${each.value}")
}

# -----------------------------------------------------------------------------
# Roles
# -----------------------------------------------------------------------------

resource "snowflake_account_role" "admin" {
  name    = var.admin_role
  comment = "Flux Admin - Full database and service management"
}

resource "snowflake_account_role" "user" {
  name    = var.user_role
  comment = "Flux User - Read access to data and execute agents"
}

# Role hierarchy (using new grant resources - old ones removed June 2024)
resource "snowflake_grant_account_role" "user_to_admin" {
  role_name        = snowflake_account_role.user.name
  parent_role_name = snowflake_account_role.admin.name
}

# Additional roles
resource "snowflake_account_role" "additional" {
  for_each = { for r in var.additional_roles : r.name => r }
  
  name    = each.value.name
  comment = each.value.comment
}

resource "snowflake_grant_account_role" "additional_hierarchy" {
  for_each = { for r in var.additional_roles : r.name => r if r.parent != null }
  
  role_name        = snowflake_account_role.additional[each.key].name
  parent_role_name = each.value.parent
}

# -----------------------------------------------------------------------------
# Database Grants (using new grant resources - old ones removed June 2024)
# -----------------------------------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "admin_database" {
  account_role_name = snowflake_account_role.admin.name
  privileges        = ["CREATE SCHEMA", "MODIFY", "MONITOR", "USAGE"]
  
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.flux.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "user_database" {
  account_role_name = snowflake_account_role.user.name
  privileges        = ["USAGE"]
  
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.flux.name
  }
}

# -----------------------------------------------------------------------------
# Schema Grants
# -----------------------------------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "admin_schema" {
  for_each = toset(var.schemas)
  
  account_role_name = snowflake_account_role.admin.name
  all_privileges    = true
  
  on_schema {
    schema_name = "\"${snowflake_database.flux.name}\".\"${each.value}\""
  }
  
  depends_on = [snowflake_schema.schemas]
}

resource "snowflake_grant_privileges_to_account_role" "user_schema" {
  for_each = toset(var.schemas)
  
  account_role_name = snowflake_account_role.user.name
  privileges        = ["USAGE"]
  
  on_schema {
    schema_name = "\"${snowflake_database.flux.name}\".\"${each.value}\""
  }
  
  depends_on = [snowflake_schema.schemas]
}

# -----------------------------------------------------------------------------
# Future Grants on Tables
# -----------------------------------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "user_select_future" {
  account_role_name = snowflake_account_role.user.name
  privileges        = ["SELECT"]
  
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${snowflake_database.flux.name}\".\"PRODUCTION\""
    }
  }
  
  depends_on = [snowflake_schema.schemas]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "database_name" {
  description = "Created database name"
  value       = snowflake_database.flux.name
}

output "admin_role" {
  description = "Admin role name"
  value       = snowflake_account_role.admin.name
}

output "user_role" {
  description = "User role name"
  value       = snowflake_account_role.user.name
}

output "schemas" {
  description = "Created schemas"
  value       = [for s in snowflake_schema.schemas : s.name]
}
