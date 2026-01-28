# =============================================================================
# Tables Module - Variables
# =============================================================================

variable "database_name" {
  description = "Database name for table creation"
  type        = string
}

variable "schema_name" {
  description = "Schema name for table creation"
  type        = string
  default     = "PRODUCTION"
}

variable "create_streaming_tables" {
  description = "Whether to create streaming target tables"
  type        = bool
  default     = true
}

variable "enable_clustering" {
  description = "Enable automatic clustering on large tables"
  type        = bool
  default     = true
}

variable "data_retention_days" {
  description = "Time Travel retention period in days"
  type        = number
  default     = 7
}
