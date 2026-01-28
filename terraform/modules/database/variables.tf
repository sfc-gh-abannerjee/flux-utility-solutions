# =============================================================================
# Database Module - Variables
# =============================================================================

variable "database_name" {
  description = "Name of the database"
  type        = string
}

variable "admin_role" {
  description = "Admin role name"
  type        = string
}

variable "user_role" {
  description = "User role name"
  type        = string
}

variable "schemas" {
  description = "List of schemas to create"
  type        = list(string)
  default     = ["PRODUCTION", "APPLICATIONS", "SECRETS"]
}

variable "schema_comments" {
  description = "Comments for schemas"
  type        = map(string)
  default = {
    PRODUCTION   = "Production data tables and views"
    APPLICATIONS = "Semantic views, agents, and application objects"
    SECRETS      = "Secrets and sensitive configuration"
  }
}

variable "data_retention_days" {
  description = "Data retention days for Time Travel"
  type        = number
  default     = 7
}

variable "additional_roles" {
  description = "Additional roles to create"
  type = list(object({
    name    = string
    comment = string
    parent  = optional(string)
  }))
  default = []
}
