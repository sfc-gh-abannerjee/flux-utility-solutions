# =============================================================================
# Cortex Search Module - Variables
# =============================================================================

variable "database_name" {
  description = "Database name"
  type        = string
}

variable "schema_name" {
  description = "Schema name for search services"
  type        = string
  default     = "APPLICATIONS"
}

variable "source_schema" {
  description = "Source schema containing base tables"
  type        = string
  default     = "PRODUCTION"
}

variable "warehouse" {
  description = "Warehouse for search service operations"
  type        = string
}

variable "target_lag" {
  description = "Target lag for search service refresh"
  type        = string
  default     = "1 hour"
}

# -----------------------------------------------------------------------------
# Customer Search Configuration
# -----------------------------------------------------------------------------

variable "create_customer_search" {
  description = "Create customer search service"
  type        = bool
  default     = true
}

variable "customer_search_name" {
  description = "Name for customer search service"
  type        = string
  default     = "CUSTOMER_SEARCH_SERVICE"
}

variable "customer_search_column" {
  description = "Column to index for customer search"
  type        = string
  default     = "SEARCH_TEXT"
}

variable "customer_attributes" {
  description = "Attributes to include in customer search results"
  type        = string
  default     = "CUSTOMER_ID, CUSTOMER_NAME, CUSTOMER_TYPE, CITY, STATE"
}

# -----------------------------------------------------------------------------
# Asset Search Configuration
# -----------------------------------------------------------------------------

variable "create_asset_search" {
  description = "Create asset search service"
  type        = bool
  default     = true
}

variable "asset_search_name" {
  description = "Name for asset search service"
  type        = string
  default     = "ASSET_SEARCH_SERVICE"
}

# -----------------------------------------------------------------------------
# Documentation Search Configuration
# -----------------------------------------------------------------------------

variable "create_docs_search" {
  description = "Create documentation search service"
  type        = bool
  default     = false
}

variable "docs_search_name" {
  description = "Name for documentation search service"
  type        = string
  default     = "TECHNICAL_DOCS_SEARCH"
}

# -----------------------------------------------------------------------------
# Access Control
# -----------------------------------------------------------------------------

variable "grant_to_roles" {
  description = "Set of roles to grant search service access"
  type        = set(string)
  default     = []
}
