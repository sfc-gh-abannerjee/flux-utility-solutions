# =============================================================================
# Cortex Agent Module - Variables
# =============================================================================

variable "database_name" {
  description = "Database name"
  type        = string
}

variable "schema_name" {
  description = "Schema name for agents"
  type        = string
  default     = "APPLICATIONS"
}

variable "warehouse" {
  description = "Warehouse for agent SQL tool"
  type        = string
}

variable "model" {
  description = "LLM model for agents"
  type        = string
  default     = "claude-3-5-sonnet"
}

# -----------------------------------------------------------------------------
# Tool Configuration
# -----------------------------------------------------------------------------

variable "enable_analyst_tool" {
  description = "Enable ANALYST tool with semantic view"
  type        = bool
  default     = true
}

variable "enable_search_tool" {
  description = "Enable SEARCH tool with Cortex Search"
  type        = bool
  default     = true
}

variable "enable_sql_tool" {
  description = "Enable direct SQL tool"
  type        = bool
  default     = true
}

variable "semantic_view_name" {
  description = "Semantic view name for ANALYST tool"
  type        = string
  default     = "AMI_ANALYTICS_SEMANTIC"
}

variable "customer_search_service" {
  description = "Customer search service name"
  type        = string
  default     = ""
}

variable "asset_search_service" {
  description = "Asset search service name"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Grid Analyst Agent Configuration
# -----------------------------------------------------------------------------

variable "create_grid_analyst" {
  description = "Create grid analyst agent"
  type        = bool
  default     = true
}

variable "grid_analyst_name" {
  description = "Name for grid analyst agent"
  type        = string
  default     = "FLUX_GRID_ANALYST"
}

# -----------------------------------------------------------------------------
# Customer Service Agent Configuration
# -----------------------------------------------------------------------------

variable "create_customer_agent" {
  description = "Create customer service agent"
  type        = bool
  default     = true
}

variable "customer_agent_name" {
  description = "Name for customer service agent"
  type        = string
  default     = "FLUX_CUSTOMER_AGENT"
}

# -----------------------------------------------------------------------------
# Engineering Agent Configuration
# -----------------------------------------------------------------------------

variable "create_engineering_agent" {
  description = "Create engineering analysis agent"
  type        = bool
  default     = true
}

variable "engineering_agent_name" {
  description = "Name for engineering agent"
  type        = string
  default     = "FLUX_ENGINEERING_AGENT"
}

# -----------------------------------------------------------------------------
# Access Control
# -----------------------------------------------------------------------------

variable "grant_to_roles" {
  description = "Set of roles to grant agent access"
  type        = set(string)
  default     = []
}
