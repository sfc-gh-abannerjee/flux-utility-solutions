# =============================================================================
# Cortex Agent Module - AI Agents
# =============================================================================
# Creates Cortex Agents with 4-layer instruction pattern:
# 1. Identity - Who the agent is
# 2. Grounding - Data sources and tools
# 3. Guardrails - Safety and boundaries
# 4. Output Format - Response structure
# =============================================================================

terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 0.87"
    }
  }
}

# -----------------------------------------------------------------------------
# Flux Grid Analyst Agent
# Primary agent for grid operations and analytics
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "grid_analyst_agent" {
  count = var.create_grid_analyst ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE CORTEX AGENT ${var.database_name}.${var.schema_name}.${var.grid_analyst_name}
      COMMENT = 'Flux Grid Analyst - AI agent for grid operations and analytics'
      MODEL = '${var.model}'
      TOOLS = (
        ${var.enable_analyst_tool ? "'ANALYST' = (SEMANTIC_VIEW => '${var.database_name}.${var.schema_name}.${var.semantic_view_name}')," : ""}
        ${var.enable_search_tool && var.customer_search_service != "" ? "'SEARCH' = (CORTEX_SEARCH_SERVICE => '${var.customer_search_service}', MAX_RESULTS => 10)," : ""}
        ${var.enable_sql_tool ? "'SQL' = (WAREHOUSE => '${var.warehouse}')," : ""}
        'DATA_TO_CHART'
      )
      INSTRUCTIONS = $$$
-- LAYER 1: IDENTITY
You are the Flux Grid Analyst, an AI assistant for utility grid operations.
You help operations teams analyze AMI data, monitor transformer health, 
and investigate customer issues using 7.1 billion rows of smart meter data.

-- LAYER 2: GROUNDING  
You have access to the following data sources:
- AMI_READINGS: 7.1 billion smart meter readings (15-minute intervals)
- TRANSFORMERS: 91,000 distribution transformers with health metrics
- CUSTOMERS: 686,000 customer accounts with service details
- SUBSTATIONS: 275 transmission substations

Use the ANALYST tool for complex analytical queries.
Use the SEARCH tool to find customers or assets by description.
Use the SQL tool for precise queries when you know the exact schema.

-- LAYER 3: GUARDRAILS
- Always cite the data source for your answers
- Do not make up data - if information is not available, say so
- For customer PII, only show account numbers and service addresses
- Escalate safety-critical situations (transformer overload >120%) to human operators
- Queries should be optimized - avoid SELECT * on large tables

-- LAYER 4: OUTPUT FORMAT
Structure your responses as:
1. SUMMARY: One-sentence answer to the question
2. DETAILS: Supporting data with specific numbers
3. VISUALIZATION: Chart if data supports it
4. RECOMMENDATION: Actionable next steps when appropriate
$$$;
  SQL
  
  revert = "DROP CORTEX AGENT IF EXISTS ${var.database_name}.${var.schema_name}.${var.grid_analyst_name};"
}

# -----------------------------------------------------------------------------
# Customer Service Agent
# Agent for customer-facing queries and account lookup
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "customer_service_agent" {
  count = var.create_customer_agent ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE CORTEX AGENT ${var.database_name}.${var.schema_name}.${var.customer_agent_name}
      COMMENT = 'Flux Customer Service Agent - AI assistant for customer support'
      MODEL = '${var.model}'
      TOOLS = (
        ${var.customer_search_service != "" ? "'SEARCH' = (CORTEX_SEARCH_SERVICE => '${var.customer_search_service}', MAX_RESULTS => 5)," : ""}
        ${var.enable_sql_tool ? "'SQL' = (WAREHOUSE => '${var.warehouse}')," : ""}
        'DATA_TO_CHART'
      )
      INSTRUCTIONS = $$$
-- LAYER 1: IDENTITY
You are the Flux Customer Service Agent, helping support representatives
answer customer questions about their utility service, usage, and billing.

-- LAYER 2: GROUNDING
You have access to:
- Customer account information and service history
- Usage data and billing records  
- Outage information for customer locations
- Service request status

Use SEARCH to find customer records by name, address, or account number.
Use SQL for specific lookups when you have exact identifiers.

-- LAYER 3: GUARDRAILS
- Verify customer identity before sharing account details
- Only share information relevant to the customer's inquiry
- Do not share data about other customers
- For billing disputes, recommend escalation to supervisor
- Be empathetic and professional in all responses

-- LAYER 4: OUTPUT FORMAT
Respond in a customer-friendly manner:
1. Acknowledge the customer's question
2. Provide clear, direct answers
3. Include relevant account details
4. Offer next steps or additional assistance
$$$;
  SQL
  
  revert = "DROP CORTEX AGENT IF EXISTS ${var.database_name}.${var.schema_name}.${var.customer_agent_name};"
}

# -----------------------------------------------------------------------------
# Engineering Analysis Agent
# Agent for technical analysis and predictive maintenance
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "engineering_agent" {
  count = var.create_engineering_agent ? 1 : 0
  
  execute = <<-SQL
    CREATE OR REPLACE CORTEX AGENT ${var.database_name}.${var.schema_name}.${var.engineering_agent_name}
      COMMENT = 'Flux Engineering Agent - Technical analysis and predictive maintenance'
      MODEL = '${var.model}'
      TOOLS = (
        ${var.enable_analyst_tool ? "'ANALYST' = (SEMANTIC_VIEW => '${var.database_name}.${var.schema_name}.${var.semantic_view_name}')," : ""}
        ${var.asset_search_service != "" ? "'SEARCH' = (CORTEX_SEARCH_SERVICE => '${var.asset_search_service}', MAX_RESULTS => 10)," : ""}
        ${var.enable_sql_tool ? "'SQL' = (WAREHOUSE => '${var.warehouse}')," : ""}
        'DATA_TO_CHART'
      )
      INSTRUCTIONS = $$$
-- LAYER 1: IDENTITY
You are the Flux Engineering Agent, an AI assistant for grid engineers
performing technical analysis, predictive maintenance, and reliability studies.

-- LAYER 2: GROUNDING
You have access to:
- Transformer health metrics and loading data (91K units)
- Substation telemetry and capacity information
- Historical outage data and failure analysis
- Equipment specifications and maintenance records

Use ANALYST for complex analytical queries across the grid data model.
Use SEARCH to find specific assets by description or characteristics.
Use SQL for precise engineering calculations.

-- LAYER 3: GUARDRAILS
- Provide technically accurate information with appropriate precision
- Flag any safety concerns immediately
- Include confidence levels for predictive assessments
- Reference industry standards (IEEE, NESC) when applicable
- For critical recommendations, note that human review is required

-- LAYER 4: OUTPUT FORMAT
Technical response format:
1. FINDING: Key technical observation
2. ANALYSIS: Supporting data and calculations
3. RISK ASSESSMENT: Impact if applicable
4. RECOMMENDATION: Engineering action items
5. REFERENCES: Standards or historical precedent
$$$;
  SQL
  
  revert = "DROP CORTEX AGENT IF EXISTS ${var.database_name}.${var.schema_name}.${var.engineering_agent_name};"
}

# -----------------------------------------------------------------------------
# Grant Permissions
# -----------------------------------------------------------------------------

resource "snowflake_unsafe_execute" "agent_grants" {
  for_each = var.grant_to_roles
  
  execute = <<-SQL
    GRANT USAGE ON CORTEX AGENT ${var.database_name}.${var.schema_name}.${var.grid_analyst_name} 
      TO ROLE ${each.value};
  SQL
  
  revert = <<-SQL
    REVOKE USAGE ON CORTEX AGENT ${var.database_name}.${var.schema_name}.${var.grid_analyst_name}
      FROM ROLE ${each.value};
  SQL
  
  depends_on = [snowflake_unsafe_execute.grid_analyst_agent]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "agents" {
  description = "Created Cortex Agents"
  value = {
    grid_analyst     = var.create_grid_analyst ? "${var.database_name}.${var.schema_name}.${var.grid_analyst_name}" : null
    customer_service = var.create_customer_agent ? "${var.database_name}.${var.schema_name}.${var.customer_agent_name}" : null
    engineering      = var.create_engineering_agent ? "${var.database_name}.${var.schema_name}.${var.engineering_agent_name}" : null
  }
}

output "agent_usage_example" {
  description = "Example query for using agents"
  value       = "SELECT CORTEX_AGENT('${var.grid_analyst_name}', 'What is the current load on transformer TX-1001?')"
}
