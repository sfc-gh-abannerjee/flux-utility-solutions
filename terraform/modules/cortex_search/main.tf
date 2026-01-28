# =============================================================================
# Cortex Search Module - Search Services
# =============================================================================
# Creates Cortex Search Services for vector-based semantic search
# Enables natural language queries across customer and asset data
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
# Customer Search Service
# Enables "Find customers affected by transformer TX-12345" queries
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "customer_search_service" {
  count = var.create_customer_search ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE CORTEX SEARCH SERVICE ${var.database_name}.${var.schema_name}.${var.customer_search_name}
      ON ${var.customer_search_column}
      ATTRIBUTES ${var.customer_attributes}
      WAREHOUSE = ${var.warehouse}
      TARGET_LAG = '${var.target_lag}'
      AS (
        SELECT 
          CUSTOMER_ID,
          CUSTOMER_NAME,
          CUSTOMER_TYPE,
          ADDRESS,
          CITY,
          STATE,
          ZIP_CODE,
          CONCAT(
            'Customer: ', CUSTOMER_NAME, '. ',
            'Type: ', CUSTOMER_TYPE, '. ',
            'Location: ', ADDRESS, ', ', CITY, ', ', STATE, ' ', ZIP_CODE, '. ',
            'Account Status: ', ACCOUNT_STATUS
          ) AS SEARCH_TEXT
        FROM ${var.database_name}.${var.source_schema}.CUSTOMERS
        WHERE ACCOUNT_STATUS = 'ACTIVE'
      )
      COMMENT = 'Customer search service for natural language queries';
  SQL
  
  revert = "DROP CORTEX SEARCH SERVICE IF EXISTS ${var.database_name}.${var.schema_name}.${var.customer_search_name};"
}

# -----------------------------------------------------------------------------
# Asset Search Service  
# Enables "Find transformers near location" queries
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "asset_search_service" {
  count = var.create_asset_search ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE CORTEX SEARCH SERVICE ${var.database_name}.${var.schema_name}.${var.asset_search_name}
      ON SEARCH_TEXT
      ATTRIBUTES ASSET_TYPE, ASSET_ID, STATUS
      WAREHOUSE = ${var.warehouse}
      TARGET_LAG = '${var.target_lag}'
      AS (
        SELECT 
          'TRANSFORMER' AS ASSET_TYPE,
          TRANSFORMER_ID AS ASSET_ID,
          TRANSFORMER_NAME AS ASSET_NAME,
          STATUS,
          CONCAT(
            'Transformer: ', TRANSFORMER_NAME, '. ',
            'ID: ', TRANSFORMER_ID, '. ',
            'Manufacturer: ', MANUFACTURER, '. ',
            'Capacity: ', RATED_CAPACITY_KVA::VARCHAR, ' KVA. ',
            'Status: ', STATUS, '. ',
            'Risk Score: ', COALESCE(RISK_SCORE::VARCHAR, 'N/A')
          ) AS SEARCH_TEXT
        FROM ${var.database_name}.${var.source_schema}.TRANSFORMERS
        
        UNION ALL
        
        SELECT
          'SUBSTATION' AS ASSET_TYPE,
          SUBSTATION_ID AS ASSET_ID,
          SUBSTATION_NAME AS ASSET_NAME,
          STATUS,
          CONCAT(
            'Substation: ', SUBSTATION_NAME, '. ',
            'ID: ', SUBSTATION_ID, '. ',
            'Voltage: ', VOLTAGE_CLASS, '. ',
            'Capacity: ', CAPACITY_MW::VARCHAR, ' MW. ',
            'Region: ', REGION, '. ',
            'Status: ', STATUS
          ) AS SEARCH_TEXT
        FROM ${var.database_name}.${var.source_schema}.SUBSTATIONS
      )
      COMMENT = 'Grid asset search service for transformers and substations';
  SQL
  
  revert = "DROP CORTEX SEARCH SERVICE IF EXISTS ${var.database_name}.${var.schema_name}.${var.asset_search_name};"
}

# -----------------------------------------------------------------------------
# Technical Documentation Search Service
# Enables "Find maintenance procedures for oil testing" queries
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "docs_search_service" {
  count = var.create_docs_search ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE CORTEX SEARCH SERVICE ${var.database_name}.${var.schema_name}.${var.docs_search_name}
      ON CHUNK_TEXT
      ATTRIBUTES DOCUMENT_NAME, DOCUMENT_TYPE, PAGE_NUMBER
      WAREHOUSE = ${var.warehouse}
      TARGET_LAG = '${var.target_lag}'
      AS (
        SELECT 
          DOCUMENT_NAME,
          DOCUMENT_TYPE,
          PAGE_NUMBER,
          CHUNK_TEXT
        FROM ${var.database_name}.${var.source_schema}.TECHNICAL_DOCUMENTATION_CHUNKS
      )
      COMMENT = 'Technical documentation search for maintenance and operational procedures';
  SQL
  
  revert = "DROP CORTEX SEARCH SERVICE IF EXISTS ${var.database_name}.${var.schema_name}.${var.docs_search_name};"
}

# -----------------------------------------------------------------------------
# Grant Permissions
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "search_service_grants" {
  for_each = var.grant_to_roles
  
  execute = <<-SQL
    GRANT USAGE ON CORTEX SEARCH SERVICE ${var.database_name}.${var.schema_name}.${var.customer_search_name} 
      TO ROLE ${each.value};
  SQL
  
  revert = <<-SQL
    REVOKE USAGE ON CORTEX SEARCH SERVICE ${var.database_name}.${var.schema_name}.${var.customer_search_name}
      FROM ROLE ${each.value};
  SQL
  
  depends_on = [snowflake_unsafe_execute.customer_search_service]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "search_services" {
  description = "Created Cortex Search services"
  value = {
    customer = var.create_customer_search ? "${var.database_name}.${var.schema_name}.${var.customer_search_name}" : null
    asset    = var.create_asset_search ? "${var.database_name}.${var.schema_name}.${var.asset_search_name}" : null
    docs     = var.create_docs_search ? "${var.database_name}.${var.schema_name}.${var.docs_search_name}" : null
  }
}

output "search_usage_example" {
  description = "Example query for using search services"
  value       = "SELECT * FROM TABLE(CORTEX_SEARCH('${var.customer_search_name}', 'residential customers in Houston', 10))"
}
