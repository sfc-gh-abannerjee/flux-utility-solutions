# =============================================================================
# Semantic View Module - Cortex Analyst Integration
# =============================================================================
# Creates Semantic Views for natural language querying via Cortex Analyst
# Note: Semantic Views require YAML definitions uploaded to stages
# =============================================================================

terraform {
  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.87"
    }
  }
}

# -----------------------------------------------------------------------------
# Stage for Semantic Model YAML Files
# -----------------------------------------------------------------------------

resource "snowflake_stage" "semantic_models" {
  database = var.database_name
  schema   = var.schema_name
  name     = var.stage_name
  
  directory = "ENABLE = TRUE"
  comment   = "Stage for Semantic View YAML definitions"
}

# -----------------------------------------------------------------------------
# Semantic View - AMI Analytics
# Note: YAML file must be uploaded to stage before creating semantic view
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "ami_semantic_view" {
  count = var.create_ami_semantic_view ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE SEMANTIC VIEW ${var.database_name}.${var.schema_name}.${var.ami_semantic_view_name}
      FROM SEMANTIC MODEL @${var.database_name}.${var.schema_name}.${var.stage_name}/${var.ami_model_filename}
      COMMENT = 'AMI Analytics Semantic View for natural language queries on 7.1B rows';
  SQL
  
  revert = "DROP SEMANTIC VIEW IF EXISTS ${var.database_name}.${var.schema_name}.${var.ami_semantic_view_name};"
  
  depends_on = [snowflake_stage.semantic_models]
}

# -----------------------------------------------------------------------------
# Semantic View - Grid Topology
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "grid_semantic_view" {
  count = var.create_grid_semantic_view ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE SEMANTIC VIEW ${var.database_name}.${var.schema_name}.${var.grid_semantic_view_name}
      FROM SEMANTIC MODEL @${var.database_name}.${var.schema_name}.${var.stage_name}/${var.grid_model_filename}
      COMMENT = 'Grid Topology Semantic View for transformer and substation analytics';
  SQL
  
  revert = "DROP SEMANTIC VIEW IF EXISTS ${var.database_name}.${var.schema_name}.${var.grid_semantic_view_name};"
  
  depends_on = [snowflake_stage.semantic_models]
}

# -----------------------------------------------------------------------------
# Semantic View - Customer 360
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "customer_semantic_view" {
  count = var.create_customer_semantic_view ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE SEMANTIC VIEW ${var.database_name}.${var.schema_name}.${var.customer_semantic_view_name}
      FROM SEMANTIC MODEL @${var.database_name}.${var.schema_name}.${var.stage_name}/${var.customer_model_filename}
      COMMENT = 'Customer 360 Semantic View for account and usage analysis';
  SQL
  
  revert = "DROP SEMANTIC VIEW IF EXISTS ${var.database_name}.${var.schema_name}.${var.customer_semantic_view_name};"
  
  depends_on = [snowflake_stage.semantic_models]
}

# -----------------------------------------------------------------------------
# Grant Permissions
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "semantic_view_grants" {
  for_each = var.grant_to_roles
  
  execute = <<-SQL
    GRANT USAGE ON SEMANTIC VIEW ${var.database_name}.${var.schema_name}.${var.ami_semantic_view_name} 
      TO ROLE ${each.value};
  SQL
  
  revert = <<-SQL
    REVOKE USAGE ON SEMANTIC VIEW ${var.database_name}.${var.schema_name}.${var.ami_semantic_view_name} 
      FROM ROLE ${each.value};
  SQL
  
  depends_on = [snowflake_unsafe_execute.ami_semantic_view]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "stage_name" {
  description = "Stage for semantic model YAML files"
  value       = snowflake_stage.semantic_models.fully_qualified_name
}

output "semantic_views" {
  description = "Created semantic views"
  value = {
    ami      = var.create_ami_semantic_view ? "${var.database_name}.${var.schema_name}.${var.ami_semantic_view_name}" : null
    grid     = var.create_grid_semantic_view ? "${var.database_name}.${var.schema_name}.${var.grid_semantic_view_name}" : null
    customer = var.create_customer_semantic_view ? "${var.database_name}.${var.schema_name}.${var.customer_semantic_view_name}" : null
  }
}

output "deployment_note" {
  description = "Important deployment instructions"
  value       = "Upload YAML files to stage before applying: PUT file://<path>/model.yaml @${var.stage_name}"
}
