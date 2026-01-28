# =============================================================================
# Warehouse Module - Main Configuration
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
# Warehouse Grants
# -----------------------------------------------------------------------------

resource "snowflake_warehouse_grant" "admin_operate" {
  for_each = var.warehouses
  
  warehouse_name = snowflake_warehouse.warehouses[each.key].name
  privilege      = "OPERATE"
  roles          = [var.admin_role]
}

resource "snowflake_warehouse_grant" "user_usage" {
  for_each = var.warehouses
  
  warehouse_name = snowflake_warehouse.warehouses[each.key].name
  privilege      = "USAGE"
  roles          = [var.user_role]
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
