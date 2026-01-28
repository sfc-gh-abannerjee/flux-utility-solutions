# =============================================================================
# Database Module - Main Configuration
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
  
  database            = snowflake_database.flux.name
  name                = each.value
  data_retention_days = var.data_retention_days
  
  comment = lookup(var.schema_comments, each.value, "Schema for ${each.value}")
}

# -----------------------------------------------------------------------------
# Roles
# -----------------------------------------------------------------------------

resource "snowflake_role" "admin" {
  name    = var.admin_role
  comment = "Flux Admin - Full database and service management"
}

resource "snowflake_role" "user" {
  name    = var.user_role
  comment = "Flux User - Read access to data and execute agents"
}

# Role hierarchy
resource "snowflake_role_grants" "user_to_admin" {
  role_name = snowflake_role.user.name
  roles     = [snowflake_role.admin.name]
}

# Additional roles
resource "snowflake_role" "additional" {
  for_each = { for r in var.additional_roles : r.name => r }
  
  name    = each.value.name
  comment = each.value.comment
}

resource "snowflake_role_grants" "additional_hierarchy" {
  for_each = { for r in var.additional_roles : r.name => r if r.parent != null }
  
  role_name = snowflake_role.additional[each.key].name
  roles     = [each.value.parent]
}

# -----------------------------------------------------------------------------
# Database Grants
# -----------------------------------------------------------------------------

resource "snowflake_database_grant" "admin_ownership" {
  database_name = snowflake_database.flux.name
  privilege     = "OWNERSHIP"
  roles         = [snowflake_role.admin.name]
}

resource "snowflake_database_grant" "user_usage" {
  database_name = snowflake_database.flux.name
  privilege     = "USAGE"
  roles         = [snowflake_role.user.name]
}

# -----------------------------------------------------------------------------
# Schema Grants
# -----------------------------------------------------------------------------

resource "snowflake_schema_grant" "admin_all" {
  for_each = toset(var.schemas)
  
  database_name = snowflake_database.flux.name
  schema_name   = each.value
  privilege     = "ALL PRIVILEGES"
  roles         = [snowflake_role.admin.name]
  
  depends_on = [snowflake_schema.schemas]
}

resource "snowflake_schema_grant" "user_usage" {
  for_each = toset(var.schemas)
  
  database_name = snowflake_database.flux.name
  schema_name   = each.value
  privilege     = "USAGE"
  roles         = [snowflake_role.user.name]
  
  depends_on = [snowflake_schema.schemas]
}

# -----------------------------------------------------------------------------
# Future Grants on Tables
# -----------------------------------------------------------------------------

resource "snowflake_table_grant" "user_select_future" {
  database_name = snowflake_database.flux.name
  schema_name   = "PRODUCTION"
  privilege     = "SELECT"
  roles         = [snowflake_role.user.name]
  on_future     = true
  
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
  value       = snowflake_role.admin.name
}

output "user_role" {
  description = "User role name"
  value       = snowflake_role.user.name
}

output "schemas" {
  description = "Created schemas"
  value       = [for s in snowflake_schema.schemas : s.name]
}
