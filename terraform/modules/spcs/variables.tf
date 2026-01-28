# =============================================================================
# SPCS Module - Variables
# =============================================================================

variable "database_name" {
  description = "Database name"
  type        = string
}

variable "schema_name" {
  description = "Schema name for SPCS objects"
  type        = string
  default     = "APPLICATIONS"
}

variable "warehouse" {
  description = "Warehouse for service operations"
  type        = string
}

# -----------------------------------------------------------------------------
# Image Repository Configuration
# -----------------------------------------------------------------------------

variable "image_registry" {
  description = "Snowflake image registry hostname"
  type        = string
}

variable "repository_name" {
  description = "Image repository name"
  type        = string
  default     = "FLUX_IMAGES"
}

variable "specs_stage_name" {
  description = "Stage name for service specifications"
  type        = string
  default     = "SPCS_SPECS"
}

# -----------------------------------------------------------------------------
# Compute Pool Configuration - Interactive
# -----------------------------------------------------------------------------

variable "create_interactive_pool" {
  description = "Create interactive compute pool"
  type        = bool
  default     = true
}

variable "interactive_pool_name" {
  description = "Name for interactive compute pool"
  type        = string
  default     = "FLUX_INTERACTIVE_POOL"
}

variable "interactive_pool_min_nodes" {
  description = "Minimum nodes for interactive pool"
  type        = number
  default     = 1
}

variable "interactive_pool_max_nodes" {
  description = "Maximum nodes for interactive pool"
  type        = number
  default     = 3
}

variable "interactive_pool_instance_family" {
  description = "Instance family for interactive pool"
  type        = string
  default     = "CPU_X64_S"
}

# -----------------------------------------------------------------------------
# Compute Pool Configuration - Streaming
# -----------------------------------------------------------------------------

variable "create_streaming_pool" {
  description = "Create streaming compute pool"
  type        = bool
  default     = true
}

variable "streaming_pool_name" {
  description = "Name for streaming compute pool"
  type        = string
  default     = "FLUX_STREAMING_POOL"
}

variable "streaming_pool_min_nodes" {
  description = "Minimum nodes for streaming pool"
  type        = number
  default     = 1
}

variable "streaming_pool_max_nodes" {
  description = "Maximum nodes for streaming pool"
  type        = number
  default     = 2
}

variable "streaming_pool_instance_family" {
  description = "Instance family for streaming pool"
  type        = string
  default     = "CPU_X64_M"
}

variable "auto_suspend_secs" {
  description = "Auto suspend timeout for compute pools"
  type        = number
  default     = 3600
}

# -----------------------------------------------------------------------------
# Flux Ops Center Configuration
# -----------------------------------------------------------------------------

variable "create_ops_center" {
  description = "Create Flux Ops Center service"
  type        = bool
  default     = true
}

variable "ops_center_service_name" {
  description = "Name for Ops Center service"
  type        = string
  default     = "FLUX_OPS_CENTER"
}

variable "ops_center_max_instances" {
  description = "Maximum instances for Ops Center"
  type        = number
  default     = 2
}

# -----------------------------------------------------------------------------
# Flux Data Forge Configuration
# -----------------------------------------------------------------------------

variable "create_data_forge" {
  description = "Create Flux Data Forge service"
  type        = bool
  default     = true
}

variable "data_forge_service_name" {
  description = "Name for Data Forge service"
  type        = string
  default     = "FLUX_DATA_FORGE"
}

variable "data_forge_max_instances" {
  description = "Maximum instances for Data Forge"
  type        = number
  default     = 2
}

# -----------------------------------------------------------------------------
# External Access Configuration
# -----------------------------------------------------------------------------

variable "external_access_integration" {
  description = "External Access Integration name"
  type        = string
  default     = "POSTGRES_EXTERNAL_ACCESS"
}

variable "postgres_host" {
  description = "PostgreSQL host for Data Forge dual-write mode"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Access Control
# -----------------------------------------------------------------------------

variable "grant_to_roles" {
  description = "Set of roles to grant service access"
  type        = set(string)
  default     = []
}
