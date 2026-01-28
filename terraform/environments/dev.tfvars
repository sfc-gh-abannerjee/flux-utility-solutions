# =============================================================================
# Development Environment Configuration
# =============================================================================
# Usage: terraform plan -var-file="environments/dev.tfvars"
# =============================================================================

environment = "dev"

# Database
database_name = "FLUX_DEV"
admin_role    = "FLUX_DEV_ADMIN"
user_role     = "FLUX_DEV_USER"

# Warehouses
warehouse_prefix       = "FLUX_DEV"
primary_warehouse_size = "XSMALL"
large_warehouse_size   = "SMALL"
cortex_warehouse_size  = "XSMALL"

# SPCS - disabled for dev
enable_spcs = false

# Tags
tags = {
  project     = "flux-utility-solutions"
  environment = "dev"
  managed_by  = "terraform"
}
