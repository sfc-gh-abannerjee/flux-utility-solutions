# =============================================================================
# Production Environment Configuration
# =============================================================================
# Usage: terraform plan -var-file="environments/prod.tfvars"
# =============================================================================

environment = "prod"

# Database
database_name = "FLUX_PROD"
admin_role    = "FLUX_PROD_ADMIN"
user_role     = "FLUX_PROD_USER"

# Warehouses
warehouse_prefix       = "FLUX_PROD"
primary_warehouse_size = "MEDIUM"
large_warehouse_size   = "LARGE"
cortex_warehouse_size  = "MEDIUM"

# SPCS - enabled for prod
enable_spcs        = true
compute_pool_name  = "FLUX_INTERACTIVE_POOL"

# Tags
tags = {
  project     = "flux-utility-solutions"
  environment = "prod"
  managed_by  = "terraform"
  owner       = "platform-team"
}
