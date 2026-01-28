# =============================================================================
# Flux Utility Solutions - Terraform Main Configuration
# =============================================================================
# Deploy Flux infrastructure to Snowflake
# Usage:
#   terraform init
#   terraform plan -var-file="environments/dev.tfvars"
#   terraform apply -var-file="environments/dev.tfvars"
# =============================================================================

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.87"
    }
  }
}

# =============================================================================
# PROVIDER CONFIGURATION
# =============================================================================

provider "snowflake" {
  role = var.terraform_role
}

# =============================================================================
# DATABASE MODULE
# =============================================================================

module "database" {
  source = "./modules/database"
  
  database_name = var.database_name
  admin_role    = var.admin_role
  user_role     = var.user_role
  
  schemas = [
    "PRODUCTION",
    "APPLICATIONS",
    "SECRETS"
  ]
}

# =============================================================================
# WAREHOUSE MODULE
# =============================================================================

module "warehouses" {
  source = "./modules/warehouse"
  
  warehouse_prefix = var.warehouse_prefix
  environment      = var.environment
  
  warehouses = {
    primary = {
      size                  = var.primary_warehouse_size
      auto_suspend          = 60
      auto_resume           = true
      min_cluster_count     = 1
      max_cluster_count     = 1
      enable_query_acceleration = false
    }
    large = {
      size                  = var.large_warehouse_size
      auto_suspend          = 120
      auto_resume           = true
      min_cluster_count     = 1
      max_cluster_count     = 2
      enable_query_acceleration = true
    }
    loading = {
      size                  = "SMALL"
      auto_suspend          = 60
      auto_resume           = true
      min_cluster_count     = 1
      max_cluster_count     = 1
      enable_query_acceleration = false
    }
    cortex = {
      size                  = var.cortex_warehouse_size
      auto_suspend          = 60
      auto_resume           = true
      min_cluster_count     = 1
      max_cluster_count     = 1
      enable_query_acceleration = false
    }
  }
  
  admin_role = module.database.admin_role
  user_role  = module.database.user_role
}

# =============================================================================
# ADDITIONAL ROLES
# Note: Core roles are created in database module
# Additional roles can be added here using snowflake_role resources
# =============================================================================

# Additional analyst role
resource "snowflake_role" "analyst" {
  name    = "${var.admin_role}_ANALYST"
  comment = "Cortex Analyst access role"
}

resource "snowflake_role_grants" "analyst_to_user" {
  role_name = snowflake_role.analyst.name
  roles     = [module.database.user_role]
}

# ETL role
resource "snowflake_role" "etl" {
  name    = "${var.admin_role}_ETL"
  comment = "ETL and data loading role"
}

resource "snowflake_role_grants" "etl_to_admin" {
  role_name = snowflake_role.etl.name
  roles     = [module.database.admin_role]
}

# Service role for SPCS
resource "snowflake_role" "service" {
  count   = var.enable_spcs ? 1 : 0
  name    = "${var.admin_role}_SERVICE"
  comment = "Service account role for SPCS"
}

resource "snowflake_role_grants" "service_to_admin" {
  count     = var.enable_spcs ? 1 : 0
  role_name = snowflake_role.service[0].name
  roles     = [module.database.admin_role]
}

# =============================================================================
# CORTEX INFRASTRUCTURE
# Note: Search Services and Agents require SQL, not Terraform
# =============================================================================

module "cortex" {
  source = "./modules/cortex"
  
  database_name = module.database.database_name
  warehouse     = module.warehouses.primary_warehouse_name
  admin_role    = module.database.admin_role
  
  # Image repository for SPCS
  create_image_repository = var.enable_spcs
  
  # Compute pool
  compute_pool_config = var.enable_spcs ? {
    name             = var.compute_pool_name
    min_nodes        = 1
    max_nodes        = 3
    instance_family  = "CPU_X64_S"
    auto_suspend_secs = 3600
  } : null
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "database_name" {
  description = "Created database name"
  value       = module.database.database_name
}

output "primary_warehouse" {
  description = "Primary warehouse name"
  value       = module.warehouses.primary_warehouse_name
}

output "admin_role" {
  description = "Admin role name"
  value       = module.database.admin_role
}

output "user_role" {
  description = "User role name"
  value       = module.database.user_role
}

output "deployment_info" {
  description = "Deployment summary"
  value = {
    environment = var.environment
    database    = module.database.database_name
    warehouses  = module.warehouses.warehouse_names
    next_steps  = "Run SQL scripts for tables, semantic views, and agents"
  }
}
