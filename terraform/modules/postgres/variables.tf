# =============================================================================
# PostgreSQL Module - Variables
# =============================================================================

# -----------------------------------------------------------------------------
# PostgreSQL Instance Configuration
# -----------------------------------------------------------------------------

variable "postgres_database_name" {
  description = "Name for PostgreSQL managed service database"
  type        = string
  default     = "FLUX_OPERATIONS_POSTGRES"
}

variable "instance_size" {
  description = "PostgreSQL instance size (XS, S, M, L, XL)"
  type        = string
  default     = "S"
  
  validation {
    condition     = contains(["XS", "S", "M", "L", "XL"], var.instance_size)
    error_message = "Instance size must be XS, S, M, L, or XL."
  }
}

variable "comment" {
  description = "Comment for PostgreSQL instance"
  type        = string
  default     = "Flux Operations PostgreSQL - Transactional OLTP layer (<20ms queries)"
}

variable "postgres_host" {
  description = "PostgreSQL host endpoint (from Snowflake managed service)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Snowflake Integration Configuration
# -----------------------------------------------------------------------------

variable "snowflake_database" {
  description = "Snowflake database for integration objects"
  type        = string
}

variable "snowflake_schema" {
  description = "Snowflake schema for integration objects"
  type        = string
  default     = "APPLICATIONS"
}

variable "secrets_schema" {
  description = "Schema for storing secrets"
  type        = string
  default     = "SECRETS"
}

variable "warehouse" {
  description = "Warehouse for CDC tasks"
  type        = string
}

# -----------------------------------------------------------------------------
# External Access Configuration
# -----------------------------------------------------------------------------

variable "create_external_access" {
  description = "Create External Access Integration for PostgreSQL"
  type        = bool
  default     = true
}

variable "eai_name" {
  description = "Name for External Access Integration"
  type        = string
  default     = "POSTGRES_EXTERNAL_ACCESS"
}

variable "postgres_username" {
  description = "PostgreSQL username for connection"
  type        = string
  default     = "flux_service"
  sensitive   = true
}

variable "postgres_password" {
  description = "PostgreSQL password for connection"
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------------------------------
# CDC Pipeline Configuration
# -----------------------------------------------------------------------------

variable "create_cdc_pipeline" {
  description = "Create CDC streams and tasks for PostgreSQL sync"
  type        = bool
  default     = true
}

variable "cdc_schedule" {
  description = "Schedule for CDC sync task (CRON or interval)"
  type        = string
  default     = "1 MINUTE"
}

# -----------------------------------------------------------------------------
# PostgreSQL Tables (Documentation)
# Note: Actual table creation happens via PostgreSQL client
# -----------------------------------------------------------------------------

variable "postgres_tables" {
  description = "Expected PostgreSQL tables (for documentation)"
  type = list(object({
    name        = string
    description = string
  }))
  default = [
    {
      name        = "operations.transformers"
      description = "Active transformer data for OLTP queries"
    },
    {
      name        = "operations.alerts"
      description = "Real-time alerts for operations dashboard"
    },
    {
      name        = "operations.work_orders"
      description = "Work order tracking for field crews"
    },
    {
      name        = "operations.audit_log"
      description = "Audit trail for compliance"
    }
  ]
}
