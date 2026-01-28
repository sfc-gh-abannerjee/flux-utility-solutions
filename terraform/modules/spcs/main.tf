# =============================================================================
# SPCS Module - Snowpark Container Services
# =============================================================================
# Creates SPCS infrastructure for Flux applications:
# - Flux Ops Center (React + DeckGL + FastAPI dashboard)
# - Flux Data Forge (Streaming synthetic data + pipelines demo)
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
# Image Repository
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "image_repository" {
  execute = <<-SQL
    CREATE IMAGE REPOSITORY IF NOT EXISTS ${var.database_name}.${var.schema_name}.${var.repository_name}
      COMMENT = 'Container image repository for Flux SPCS applications';
  SQL
  
  revert = "DROP IMAGE REPOSITORY IF EXISTS ${var.database_name}.${var.schema_name}.${var.repository_name};"
}

# -----------------------------------------------------------------------------
# Compute Pools
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "interactive_pool" {
  count = var.create_interactive_pool ? 1 : 0
  
  execute = <<-SQL
    CREATE COMPUTE POOL IF NOT EXISTS ${var.interactive_pool_name}
      MIN_NODES = ${var.interactive_pool_min_nodes}
      MAX_NODES = ${var.interactive_pool_max_nodes}
      INSTANCE_FAMILY = ${var.interactive_pool_instance_family}
      AUTO_SUSPEND_SECS = ${var.auto_suspend_secs}
      AUTO_RESUME = TRUE
      COMMENT = 'Compute pool for Flux interactive applications (Ops Center)';
  SQL
  
  revert = "DROP COMPUTE POOL IF EXISTS ${var.interactive_pool_name};"
}

resource "snowflake_unsafe_execute" "streaming_pool" {
  count = var.create_streaming_pool ? 1 : 0
  
  execute = <<-SQL
    CREATE COMPUTE POOL IF NOT EXISTS ${var.streaming_pool_name}
      MIN_NODES = ${var.streaming_pool_min_nodes}
      MAX_NODES = ${var.streaming_pool_max_nodes}
      INSTANCE_FAMILY = ${var.streaming_pool_instance_family}
      AUTO_SUSPEND_SECS = ${var.auto_suspend_secs}
      AUTO_RESUME = TRUE
      COMMENT = 'Compute pool for Flux Data Forge streaming services';
  SQL
  
  revert = "DROP COMPUTE POOL IF EXISTS ${var.streaming_pool_name};"
}

# -----------------------------------------------------------------------------
# Service Specification Stage
# -----------------------------------------------------------------------------

resource "snowflake_stage" "service_specs" {
  database = var.database_name
  schema   = var.schema_name
  name     = var.specs_stage_name
  
  directory = "ENABLE = TRUE"
  comment   = "Stage for SPCS service specification YAML files"
}

# -----------------------------------------------------------------------------
# Flux Ops Center Service
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "ops_center_service" {
  count = var.create_ops_center ? 1 : 0
  
  execute = <<-SQL
    CREATE SERVICE IF NOT EXISTS ${var.database_name}.${var.schema_name}.${var.ops_center_service_name}
      IN COMPUTE POOL ${var.interactive_pool_name}
      FROM SPECIFICATION $$
spec:
  containers:
    - name: flux-ops-center
      image: ${var.image_registry}/${var.database_name}/${var.schema_name}/${var.repository_name}/flux-ops-center:latest
      env:
        SNOWFLAKE_WAREHOUSE: ${var.warehouse}
        SNOWFLAKE_DATABASE: ${var.database_name}
        APP_ENV: production
      resources:
        requests:
          cpu: "1"
          memory: "2Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
  endpoints:
    - name: flux-ui
      port: 8501
      public: true
    - name: flux-api  
      port: 8000
      public: true
$$
      MIN_INSTANCES = 1
      MAX_INSTANCES = ${var.ops_center_max_instances}
      EXTERNAL_ACCESS_INTEGRATIONS = (${var.external_access_integration})
      COMMENT = 'Flux Ops Center - React/DeckGL dashboard for grid operations';
  SQL
  
  revert = "DROP SERVICE IF EXISTS ${var.database_name}.${var.schema_name}.${var.ops_center_service_name};"
  
  depends_on = [
    snowflake_unsafe_execute.image_repository,
    snowflake_unsafe_execute.interactive_pool
  ]
}

# -----------------------------------------------------------------------------
# Flux Data Forge Service
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "data_forge_service" {
  count = var.create_data_forge ? 1 : 0
  
  execute = <<-SQL
    CREATE SERVICE IF NOT EXISTS ${var.database_name}.${var.schema_name}.${var.data_forge_service_name}
      IN COMPUTE POOL ${var.streaming_pool_name}
      FROM SPECIFICATION $$
spec:
  containers:
    - name: flux-data-forge
      image: ${var.image_registry}/${var.database_name}/${var.schema_name}/${var.repository_name}/flux-data-forge:latest
      env:
        SNOWFLAKE_WAREHOUSE: ${var.warehouse}
        SNOWFLAKE_DATABASE: ${var.database_name}
        POSTGRES_HOST: ${var.postgres_host}
        APP_ENV: production
      resources:
        requests:
          cpu: "2"
          memory: "4Gi"
        limits:
          cpu: "4"
          memory: "8Gi"
      secrets:
        - snowflakeName: ${var.database_name}.SECRETS.POSTGRES_CREDENTIALS
          secretKeyRef:
            name: postgres-creds
            key: password
          envVarName: POSTGRES_PASSWORD
  endpoints:
    - name: forge-ui
      port: 8501
      public: true
    - name: forge-api
      port: 8000
      public: true
$$
      MIN_INSTANCES = 1
      MAX_INSTANCES = ${var.data_forge_max_instances}
      EXTERNAL_ACCESS_INTEGRATIONS = (${var.external_access_integration})
      COMMENT = 'Flux Data Forge - Streaming synthetic data generator with 4 pipeline modes';
  SQL
  
  revert = "DROP SERVICE IF EXISTS ${var.database_name}.${var.schema_name}.${var.data_forge_service_name};"
  
  depends_on = [
    snowflake_unsafe_execute.image_repository,
    snowflake_unsafe_execute.streaming_pool
  ]
}

# -----------------------------------------------------------------------------
# Service Functions (UDFs for calling services)
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "ops_center_function" {
  count = var.create_ops_center ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE FUNCTION ${var.database_name}.${var.schema_name}.GET_OPS_CENTER_URL()
      RETURNS VARCHAR
      AS
      $$
        SELECT SYSTEM$GET_SERVICE_DNS('${var.database_name}.${var.schema_name}.${var.ops_center_service_name}', 'flux-ui')
      $$;
  SQL
  
  revert = "DROP FUNCTION IF EXISTS ${var.database_name}.${var.schema_name}.GET_OPS_CENTER_URL();"
  
  depends_on = [snowflake_unsafe_execute.ops_center_service]
}

resource "snowflake_unsafe_execute" "data_forge_function" {
  count = var.create_data_forge ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE FUNCTION ${var.database_name}.${var.schema_name}.GET_DATA_FORGE_URL()
      RETURNS VARCHAR
      AS
      $$
        SELECT SYSTEM$GET_SERVICE_DNS('${var.database_name}.${var.schema_name}.${var.data_forge_service_name}', 'forge-ui')
      $$;
  SQL
  
  revert = "DROP FUNCTION IF EXISTS ${var.database_name}.${var.schema_name}.GET_DATA_FORGE_URL();"
  
  depends_on = [snowflake_unsafe_execute.data_forge_service]
}

# -----------------------------------------------------------------------------
# Grant Permissions
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "service_grants" {
  for_each = var.grant_to_roles
  
  execute = <<-SQL
    GRANT USAGE ON SERVICE ${var.database_name}.${var.schema_name}.${var.ops_center_service_name} 
      TO ROLE ${each.value};
    GRANT USAGE ON SERVICE ${var.database_name}.${var.schema_name}.${var.data_forge_service_name} 
      TO ROLE ${each.value};
  SQL
  
  revert = <<-SQL
    REVOKE USAGE ON SERVICE ${var.database_name}.${var.schema_name}.${var.ops_center_service_name}
      FROM ROLE ${each.value};
    REVOKE USAGE ON SERVICE ${var.database_name}.${var.schema_name}.${var.data_forge_service_name}
      FROM ROLE ${each.value};
  SQL
  
  depends_on = [
    snowflake_unsafe_execute.ops_center_service,
    snowflake_unsafe_execute.data_forge_service
  ]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "image_repository" {
  description = "Image repository path"
  value       = "${var.image_registry}/${var.database_name}/${var.schema_name}/${var.repository_name}"
}

output "compute_pools" {
  description = "Created compute pools"
  value = {
    interactive = var.create_interactive_pool ? var.interactive_pool_name : null
    streaming   = var.create_streaming_pool ? var.streaming_pool_name : null
  }
}

output "services" {
  description = "Created SPCS services"
  value = {
    ops_center = var.create_ops_center ? "${var.database_name}.${var.schema_name}.${var.ops_center_service_name}" : null
    data_forge = var.create_data_forge ? "${var.database_name}.${var.schema_name}.${var.data_forge_service_name}" : null
  }
}

output "service_urls" {
  description = "Service URL retrieval functions"
  value = {
    ops_center = var.create_ops_center ? "SELECT ${var.database_name}.${var.schema_name}.GET_OPS_CENTER_URL()" : null
    data_forge = var.create_data_forge ? "SELECT ${var.database_name}.${var.schema_name}.GET_DATA_FORGE_URL()" : null
  }
}

output "docker_push_commands" {
  description = "Commands to push images to repository"
  value = <<-EOT
    # Login to Snowflake registry
    docker login ${var.image_registry}
    
    # Push Flux Ops Center
    docker tag flux-ops-center:latest ${var.image_registry}/${var.database_name}/${var.schema_name}/${var.repository_name}/flux-ops-center:latest
    docker push ${var.image_registry}/${var.database_name}/${var.schema_name}/${var.repository_name}/flux-ops-center:latest
    
    # Push Flux Data Forge
    docker tag flux-data-forge:latest ${var.image_registry}/${var.database_name}/${var.schema_name}/${var.repository_name}/flux-data-forge:latest
    docker push ${var.image_registry}/${var.database_name}/${var.schema_name}/${var.repository_name}/flux-data-forge:latest
  EOT
}
