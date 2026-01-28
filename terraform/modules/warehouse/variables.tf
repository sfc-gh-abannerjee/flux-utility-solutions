# =============================================================================
# Warehouse Module - Variables
# =============================================================================

variable "warehouse_prefix" {
  description = "Prefix for warehouse names"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "warehouses" {
  description = "Warehouse configurations"
  type = map(object({
    size                      = string
    auto_suspend              = number
    auto_resume               = bool
    min_cluster_count         = number
    max_cluster_count         = number
    enable_query_acceleration = bool
  }))
}

variable "admin_role" {
  description = "Admin role for OPERATE grant"
  type        = string
}

variable "user_role" {
  description = "User role for USAGE grant"
  type        = string
}
