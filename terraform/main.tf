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
      source  = "snowflakedb/snowflake"
      version = ">= 2.11.0"  # Required for snowflake_semantic_view resource
    }
  }
}

# =============================================================================
# PROVIDER CONFIGURATION
# =============================================================================
# Provider uses environment variables for credentials:
# - SNOWFLAKE_ACCOUNT or TF_VAR_snowflake_account
# - SNOWFLAKE_USER or TF_VAR_snowflake_user
# - SNOWFLAKE_PASSWORD or TF_VAR_snowflake_password

provider "snowflake" {
  role              = var.terraform_role
  organization_name = var.snowflake_org
  account_name      = var.snowflake_account
  user              = var.snowflake_user
  password          = var.snowflake_password
  
  # Enable preview features for notebooks and semantic views
  preview_features_enabled = var.enable_preview_features ? [
    "snowflake_notebook_resource",
    "snowflake_notebooks_datasource",
    "snowflake_semantic_view_resource",
    "snowflake_semantic_views_datasource"
  ] : []
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
resource "snowflake_account_role" "analyst" {
  name    = "${var.admin_role}_ANALYST"
  comment = "Cortex Analyst access role"
}

resource "snowflake_grant_account_role" "analyst_to_user" {
  role_name        = snowflake_account_role.analyst.name
  parent_role_name = module.database.user_role
}

# ETL role
resource "snowflake_account_role" "etl" {
  name    = "${var.admin_role}_ETL"
  comment = "ETL and data loading role"
}

resource "snowflake_grant_account_role" "etl_to_admin" {
  role_name        = snowflake_account_role.etl.name
  parent_role_name = module.database.admin_role
}

# Service role for SPCS
resource "snowflake_account_role" "service" {
  count   = var.enable_spcs ? 1 : 0
  name    = "${var.admin_role}_SERVICE"
  comment = "Service account role for SPCS"
}

resource "snowflake_grant_account_role" "service_to_admin" {
  count            = var.enable_spcs ? 1 : 0
  role_name        = snowflake_account_role.service[0].name
  parent_role_name = module.database.admin_role
}

# =============================================================================
# CORTEX INFRASTRUCTURE
# Includes: Semantic Views, Search Services setup, SPCS compute
# Note: Agents still require SQL deployment
# =============================================================================

module "cortex" {
  source = "./modules/cortex"
  
  database_name = module.database.database_name
  warehouse     = module.warehouses.primary_warehouse_name
  admin_role    = module.database.admin_role
  
  # Semantic View configuration
  create_semantic_view = var.create_semantic_view
  semantic_view_name   = "UTILITY_SEMANTIC_VIEW"
  user_role            = module.database.user_role
  
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
# STREAMLIT APPLICATIONS
# =============================================================================

module "streamlit" {
  source = "./modules/streamlit"
  
  database_name  = module.database.database_name
  schema_name    = "APPLICATIONS"
  warehouse_name = module.warehouses.primary_warehouse_name
}

# =============================================================================
# NOTEBOOKS (Preview Feature)
# Requires: enable_preview_features = true
# =============================================================================

module "notebooks" {
  source = "./modules/notebook"
  
  database_name    = module.database.database_name
  schema_name      = "APPLICATIONS"
  warehouse_name   = module.warehouses.primary_warehouse_name
  create_notebooks = var.enable_preview_features && var.create_notebooks
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
    environment       = var.environment
    database          = module.database.database_name
    warehouses        = module.warehouses.warehouse_names
    streamlit_apps    = module.streamlit.streamlit_apps
    notebooks_enabled = var.enable_preview_features && var.create_notebooks
    next_steps        = "Upload files to stages, then run SQL scripts for tables and agents"
  }
}
