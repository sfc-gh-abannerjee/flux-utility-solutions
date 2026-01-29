# =============================================================================
# Warehouse Module - Main Configuration
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
# Warehouses
# -----------------------------------------------------------------------------

resource "snowflake_warehouse" "warehouses" {
  for_each = var.warehouses
  
  name           = "${var.warehouse_prefix}_${upper(each.key)}_WH"
  warehouse_size = each.value.size
  
  auto_suspend                  = each.value.auto_suspend
  auto_resume                   = each.value.auto_resume
  min_cluster_count             = each.value.min_cluster_count
  max_cluster_count             = each.value.max_cluster_count
  enable_query_acceleration     = each.value.enable_query_acceleration
  
  comment = "Flux ${each.key} warehouse for ${var.environment}"
}

# -----------------------------------------------------------------------------
# Warehouse Grants (using new grant resources - old ones removed June 2024)
# -----------------------------------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "admin_operate" {
  for_each = var.warehouses
  
  account_role_name = var.admin_role
  privileges        = ["OPERATE", "USAGE", "MONITOR"]
  
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.warehouses[each.key].name
  }
}

resource "snowflake_grant_privileges_to_account_role" "user_usage" {
  for_each = var.warehouses
  
  account_role_name = var.user_role
  privileges        = ["USAGE"]
  
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.warehouses[each.key].name
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "warehouse_names" {
  description = "Created warehouse names"
  value       = { for k, v in snowflake_warehouse.warehouses : k => v.name }
}

output "primary_warehouse_name" {
  description = "Primary warehouse name"
  value       = snowflake_warehouse.warehouses["primary"].name
}
