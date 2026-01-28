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
