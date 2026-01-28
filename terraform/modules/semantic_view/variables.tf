# =============================================================================
# Semantic View Module - Variables
# =============================================================================

variable "database_name" {
  description = "Database name"
  type        = string
}

variable "schema_name" {
  description = "Schema name for semantic views"
  type        = string
  default     = "APPLICATIONS"
}

variable "stage_name" {
  description = "Stage name for YAML model files"
  type        = string
  default     = "SEMANTIC_MODELS"
}

# -----------------------------------------------------------------------------
# AMI Semantic View Configuration
# -----------------------------------------------------------------------------

variable "create_ami_semantic_view" {
  description = "Create AMI analytics semantic view"
  type        = bool
  default     = true
}

variable "ami_semantic_view_name" {
  description = "Name for AMI semantic view"
  type        = string
  default     = "AMI_ANALYTICS_SEMANTIC"
}

variable "ami_model_filename" {
  description = "Filename for AMI semantic model YAML"
  type        = string
  default     = "ami_domain.yaml"
}

# -----------------------------------------------------------------------------
# Grid Topology Semantic View Configuration  
# -----------------------------------------------------------------------------

variable "create_grid_semantic_view" {
  description = "Create grid topology semantic view"
  type        = bool
  default     = true
}

variable "grid_semantic_view_name" {
  description = "Name for grid topology semantic view"
  type        = string
  default     = "GRID_TOPOLOGY_SEMANTIC"
}

variable "grid_model_filename" {
  description = "Filename for grid semantic model YAML"
  type        = string
  default     = "grid_topology_domain.yaml"
}

# -----------------------------------------------------------------------------
# Customer 360 Semantic View Configuration
# -----------------------------------------------------------------------------

variable "create_customer_semantic_view" {
  description = "Create customer 360 semantic view"
  type        = bool
  default     = true
}

variable "customer_semantic_view_name" {
  description = "Name for customer semantic view"
  type        = string
  default     = "CUSTOMER_360_SEMANTIC"
}

variable "customer_model_filename" {
  description = "Filename for customer semantic model YAML"
  type        = string
  default     = "customer_domain.yaml"
}

# -----------------------------------------------------------------------------
# Access Control
# -----------------------------------------------------------------------------

variable "grant_to_roles" {
  description = "Set of roles to grant semantic view access"
  type        = set(string)
  default     = []
}
