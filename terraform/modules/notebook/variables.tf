# Notebook Module Variables
# =============================================================================

variable "database_name" {
  description = "Target database name"
  type        = string
}

variable "schema_name" {
  description = "Schema for notebooks"
  type        = string
  default     = "APPLICATIONS"
}

variable "warehouse_name" {
  description = "Query warehouse for notebooks"
  type        = string
}

variable "stage_name" {
  description = "Stage containing notebook files"
  type        = string
  default     = "NOTEBOOKS_STAGE"
}

variable "create_notebooks" {
  description = "Whether to create notebook resources (requires preview feature enabled)"
  type        = bool
  default     = true
}
