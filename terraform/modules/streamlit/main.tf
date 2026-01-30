# Streamlit Module - Deploy Streamlit in Snowflake Applications
# =============================================================================
# This module deploys all Flux Utility Solutions Streamlit apps
#
# Note: As of provider v2.12, snowflake_streamlit resource is available
# =============================================================================

variable "database_name" {
  description = "Target database name"
  type        = string
}

variable "schema_name" {
  description = "Schema for Streamlit apps"
  type        = string
  default     = "APPLICATIONS"
}

variable "warehouse_name" {
  description = "Query warehouse for Streamlit apps"
  type        = string
}

variable "stage_name" {
  description = "Stage containing Streamlit app files"
  type        = string
  default     = "STREAMLIT_STAGE"
}

# -----------------------------------------------------------------------------
# Stage for Streamlit Files
# -----------------------------------------------------------------------------

resource "snowflake_stage" "streamlit_stage" {
  database = var.database_name
  schema   = var.schema_name
  name     = var.stage_name
  comment  = "Stage for Streamlit application files"
  
  directory = "ENABLE = TRUE"
}

# -----------------------------------------------------------------------------
# H3 Geospatial Analytics App
# -----------------------------------------------------------------------------

resource "snowflake_streamlit" "geospatial_h3" {
  database  = var.database_name
  schema    = var.schema_name
  name      = "FLUX_GEOSPATIAL_H3_APP"
  
  stage     = "${var.database_name}.${var.schema_name}.${snowflake_stage.streamlit_stage.name}"
  directory_location = "geospatial"
  main_file = "streamlit_h3_app.py"
  
  query_warehouse = var.warehouse_name
  title           = "Flux Geospatial Analytics"
  comment         = "H3 hexagonal grid visualization for utility infrastructure analysis"
}

# -----------------------------------------------------------------------------
# Grid Map App
# -----------------------------------------------------------------------------

resource "snowflake_streamlit" "grid_map" {
  database  = var.database_name
  schema    = var.schema_name
  name      = "FLUX_GRID_MAP_APP"
  
  stage     = "${var.database_name}.${var.schema_name}.${snowflake_stage.streamlit_stage.name}"
  main_file = "grid_map.py"
  
  query_warehouse = var.warehouse_name
  title           = "Flux Grid Map"
  comment         = "Real-time grid topology and transformer status visualization"
}

# -----------------------------------------------------------------------------
# Load Analytics App
# -----------------------------------------------------------------------------

resource "snowflake_streamlit" "load_analytics" {
  database  = var.database_name
  schema    = var.schema_name
  name      = "FLUX_LOAD_ANALYTICS_APP"
  
  stage     = "${var.database_name}.${var.schema_name}.${snowflake_stage.streamlit_stage.name}"
  main_file = "load_analytics.py"
  
  query_warehouse = var.warehouse_name
  title           = "Flux Load Analytics"
  comment         = "Transformer load analysis and capacity planning dashboard"
}

# -----------------------------------------------------------------------------
# Outage Dashboard App
# -----------------------------------------------------------------------------

resource "snowflake_streamlit" "outage_dashboard" {
  database  = var.database_name
  schema    = var.schema_name
  name      = "FLUX_OUTAGE_DASHBOARD_APP"
  
  stage     = "${var.database_name}.${var.schema_name}.${snowflake_stage.streamlit_stage.name}"
  main_file = "outage_dashboard.py"
  
  query_warehouse = var.warehouse_name
  title           = "Flux Outage Dashboard"
  comment         = "Outage tracking and restoration monitoring dashboard"
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "streamlit_stage" {
  description = "Streamlit stage name"
  value       = snowflake_stage.streamlit_stage.name
}

output "streamlit_apps" {
  description = "Deployed Streamlit applications"
  value = {
    geospatial_h3   = snowflake_streamlit.geospatial_h3.name
    grid_map        = snowflake_streamlit.grid_map.name
    load_analytics  = snowflake_streamlit.load_analytics.name
    outage_dashboard = snowflake_streamlit.outage_dashboard.name
  }
}
