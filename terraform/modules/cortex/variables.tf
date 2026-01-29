# =============================================================================
# Cortex Module - Variables
# =============================================================================

variable "database_name" {
  description = "Database name"
  type        = string
}

variable "warehouse" {
  description = "Warehouse for Cortex operations"
  type        = string
}

variable "admin_role" {
  description = "Admin role"
  type        = string
}

variable "create_image_repository" {
  description = "Create image repository for SPCS"
  type        = bool
  default     = false
}

variable "compute_pool_config" {
  description = "Compute pool configuration"
  type = object({
    name              = string
    min_nodes         = number
    max_nodes         = number
    instance_family   = string
    auto_suspend_secs = number
  })
  default = null
}

# -----------------------------------------------------------------------------
# Semantic View Configuration
# -----------------------------------------------------------------------------

variable "create_semantic_view" {
  description = "Create the utility semantic view"
  type        = bool
  default     = true
}

variable "semantic_view_name" {
  description = "Name of the semantic view"
  type        = string
  default     = "UTILITY_SEMANTIC_VIEW"
}

variable "user_role" {
  description = "User role to grant SELECT on semantic view"
  type        = string
  default     = "PUBLIC"
}
