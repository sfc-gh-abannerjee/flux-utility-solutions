# =============================================================================
# Flux Utility Solutions - Terraform Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Snowflake Connection
# -----------------------------------------------------------------------------

variable "snowflake_org" {
  description = "Snowflake organization name"
  type        = string
  default     = ""
}

variable "snowflake_account" {
  description = "Snowflake account name"
  type        = string
  default     = ""
}

variable "snowflake_user" {
  description = "Snowflake username"
  type        = string
  default     = ""
}

variable "snowflake_password" {
  description = "Snowflake password or programmatic key"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Environment
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "terraform_role" {
  description = "Snowflake role for Terraform to use"
  type        = string
  default     = "ACCOUNTADMIN"
}

# -----------------------------------------------------------------------------
# Database Configuration
# -----------------------------------------------------------------------------

variable "database_name" {
  description = "Name of the Flux database"
  type        = string
  default     = "FLUX_DEV"
}

variable "admin_role" {
  description = "Admin role name"
  type        = string
  default     = "FLUX_DEV_ADMIN"
}

variable "user_role" {
  description = "User role name"
  type        = string
  default     = "FLUX_DEV_USER"
}

# -----------------------------------------------------------------------------
# Warehouse Configuration
# -----------------------------------------------------------------------------

variable "warehouse_prefix" {
  description = "Prefix for warehouse names"
  type        = string
  default     = "FLUX_DEV"
}

variable "primary_warehouse_size" {
  description = "Size of primary warehouse"
  type        = string
  default     = "SMALL"
  
  validation {
    condition     = contains(["XSMALL", "SMALL", "MEDIUM", "LARGE", "XLARGE"], var.primary_warehouse_size)
    error_message = "Invalid warehouse size."
  }
}

variable "large_warehouse_size" {
  description = "Size of large warehouse for heavy queries"
  type        = string
  default     = "MEDIUM"
}

variable "cortex_warehouse_size" {
  description = "Size of Cortex AI warehouse"
  type        = string
  default     = "SMALL"
}

# -----------------------------------------------------------------------------
# SPCS Configuration
# -----------------------------------------------------------------------------

variable "enable_spcs" {
  description = "Enable Snowpark Container Services"
  type        = bool
  default     = false
}

variable "compute_pool_name" {
  description = "Name of the compute pool"
  type        = string
  default     = "FLUX_INTERACTIVE_POOL"
}

# -----------------------------------------------------------------------------
# Cortex Configuration
# -----------------------------------------------------------------------------

variable "create_semantic_view" {
  description = "Create semantic view for Cortex Analyst"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Preview Features (v2.11.0+)
# -----------------------------------------------------------------------------

variable "enable_preview_features" {
  description = "Enable Terraform provider preview features (notebooks, semantic views)"
  type        = bool
  default     = false
}

variable "create_notebooks" {
  description = "Create notebook resources (requires enable_preview_features = true)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    project     = "flux-utility-solutions"
    managed_by  = "terraform"
  }
}
