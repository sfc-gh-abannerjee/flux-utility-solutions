# Notebook Module - Deploy Snowflake Notebooks
# =============================================================================
# This module deploys Flux Utility Solutions notebooks to Snowflake
#
# IMPORTANT: Requires Terraform provider v2.11.0+ with preview features enabled
# Add to provider config: preview_features_enabled = ["snowflake_notebook_resource"]
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
  description = "Whether to create notebook resources (requires preview feature)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Stage for Notebook Files
# -----------------------------------------------------------------------------

resource "snowflake_stage" "notebooks_stage" {
  database = var.database_name
  schema   = var.schema_name
  name     = var.stage_name
  comment  = "Stage for Snowflake Notebook files"
  
  directory = "ENABLE = TRUE"
}

# -----------------------------------------------------------------------------
# Setup Notebooks
# -----------------------------------------------------------------------------

resource "snowflake_notebook" "full_deployment" {
  count = var.create_notebooks ? 1 : 0
  
  database  = var.database_name
  schema    = var.schema_name
  name      = "FLUX_FULL_DEPLOYMENT"
  
  from_source  = "${var.database_name}.${var.schema_name}.${snowflake_stage.notebooks_stage.name}"
  main_file    = "setup/01_full_deployment.ipynb"
  
  query_warehouse = var.warehouse_name
  comment         = "Complete Flux Utility Solutions deployment notebook"
}

resource "snowflake_notebook" "load_seed_data" {
  count = var.create_notebooks ? 1 : 0
  
  database  = var.database_name
  schema    = var.schema_name
  name      = "FLUX_LOAD_SEED_DATA"
  
  from_source  = "${var.database_name}.${var.schema_name}.${snowflake_stage.notebooks_stage.name}"
  main_file    = "setup/02_load_seed_data.ipynb"
  
  query_warehouse = var.warehouse_name
  comment         = "Load seed data and sample AMI readings"
}

# -----------------------------------------------------------------------------
# Demo Notebooks
# -----------------------------------------------------------------------------

resource "snowflake_notebook" "ami_analytics" {
  count = var.create_notebooks ? 1 : 0
  
  database  = var.database_name
  schema    = var.schema_name
  name      = "FLUX_AMI_ANALYTICS"
  
  from_source  = "${var.database_name}.${var.schema_name}.${snowflake_stage.notebooks_stage.name}"
  main_file    = "demos/ami_analytics.ipynb"
  
  query_warehouse = var.warehouse_name
  comment         = "AMI smart meter analytics and consumption patterns"
}

resource "snowflake_notebook" "customer_360_search" {
  count = var.create_notebooks ? 1 : 0
  
  database  = var.database_name
  schema    = var.schema_name
  name      = "FLUX_CUSTOMER_360_SEARCH"
  
  from_source  = "${var.database_name}.${var.schema_name}.${snowflake_stage.notebooks_stage.name}"
  main_file    = "demos/customer_360_search.ipynb"
  
  query_warehouse = var.warehouse_name
  comment         = "Customer 360 with Cortex Search integration"
}

resource "snowflake_notebook" "geospatial_h3" {
  count = var.create_notebooks ? 1 : 0
  
  database  = var.database_name
  schema    = var.schema_name
  name      = "FLUX_GEOSPATIAL_H3"
  
  from_source  = "${var.database_name}.${var.schema_name}.${snowflake_stage.notebooks_stage.name}"
  main_file    = "demos/geospatial_h3.ipynb"
  
  query_warehouse = var.warehouse_name
  comment         = "H3 geospatial analytics and hexagonal grid visualization"
}

resource "snowflake_notebook" "transformer_risk_ml" {
  count = var.create_notebooks ? 1 : 0
  
  database  = var.database_name
  schema    = var.schema_name
  name      = "FLUX_TRANSFORMER_RISK_ML"
  
  from_source  = "${var.database_name}.${var.schema_name}.${snowflake_stage.notebooks_stage.name}"
  main_file    = "demos/transformer_risk_ml.ipynb"
  
  query_warehouse = var.warehouse_name
  comment         = "Transformer risk scoring with ML models"
}

# -----------------------------------------------------------------------------
# Advanced Notebooks
# -----------------------------------------------------------------------------

resource "snowflake_notebook" "cascade_simulation" {
  count = var.create_notebooks ? 1 : 0
  
  database  = var.database_name
  schema    = var.schema_name
  name      = "FLUX_CASCADE_SIMULATION"
  
  from_source  = "${var.database_name}.${var.schema_name}.${snowflake_stage.notebooks_stage.name}"
  main_file    = "advanced/cascade_simulation.ipynb"
  
  query_warehouse = var.warehouse_name
  comment         = "Cascade failure simulation and what-if analysis"
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "notebooks_stage" {
  description = "Notebooks stage name"
  value       = snowflake_stage.notebooks_stage.name
}

output "notebooks" {
  description = "Deployed notebook names"
  value = var.create_notebooks ? {
    full_deployment     = snowflake_notebook.full_deployment[0].name
    load_seed_data      = snowflake_notebook.load_seed_data[0].name
    ami_analytics       = snowflake_notebook.ami_analytics[0].name
    customer_360_search = snowflake_notebook.customer_360_search[0].name
    geospatial_h3       = snowflake_notebook.geospatial_h3[0].name
    transformer_risk_ml = snowflake_notebook.transformer_risk_ml[0].name
    cascade_simulation  = snowflake_notebook.cascade_simulation[0].name
  } : {}
}
