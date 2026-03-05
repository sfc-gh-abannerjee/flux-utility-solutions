-- =============================================================================
-- 10_cortex_agent.sql
-- Flux Utility Solutions - Grid Intelligence Cortex Agent
-- =============================================================================
-- Purpose: Create Cortex Agent for natural language grid analytics
-- Dependencies: 08_semantic_view.sql
--
-- Variable Templating (Snow CLI Jinja2):
--   <% database %>   - Target database name (e.g., FLUX_DEMO)
--   <% user_role %>  - Role to grant agent usage
--
-- Usage:
--   snow sql -f scripts/10_cortex_agent.sql -D "database=YOUR_DATABASE" -D "user_role=PUBLIC"
--
-- NOTE: Agents are invoked via the REST API or Snowsight UI, NOT via SQL functions.
--       There is no SNOWFLAKE.CORTEX.INVOKE_AGENT() function - use the /api/agents endpoint.
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE SCHEMA APPLICATIONS;

-- -----------------------------------------------------------------------------
-- 1. CREATE CORTEX AGENT
-- -----------------------------------------------------------------------------
-- Agents use a YAML specification within FROM SPECIFICATION clause
-- The spec defines: models, instructions, tools, and tool_resources
--
-- Key requirements:
--   - models.orchestration: The LLM to use (e.g., claude-sonnet-4-5)
--   - tools[].tool_spec.type: Must match valid tool types (cortex_analyst_text_to_sql, cortex_search, etc.)
--   - tool_resources: Must reference valid semantic views or search services
--
-- IMPORTANT: Do NOT include sample_questions in the spec - it's not a valid field

CREATE OR REPLACE AGENT GRID_INTELLIGENCE_AGENT
    COMMENT = 'Grid Intelligence Agent - Utility operations assistant for AMI analytics, transformer health, and customer lookup'
    FROM SPECIFICATION $$
models:
  orchestration: claude-sonnet-4-5

orchestration:
  budget:
    seconds: 60
    tokens: 32000

instructions:
  system: |
    You are the Grid Intelligence Assistant, a specialized AI assistant for utility grid operations.
    You help operations personnel, engineers, and analysts understand grid performance, 
    customer usage patterns, and asset health.
    
    ## Your Capabilities
    - AMI Data: Energy consumption, voltage readings, meter performance (7.1B+ readings)
    - Transformer Health: Load factors, thermal stress, overloading risk (91K assets)
    - Customer Information: Account lookup, segmentation, service addresses (686K customers)
    - Grid Operations: Circuit status, outage patterns, load analysis
    
    ## Data Context
    - Time Range: July-August 2024 and July-August 2025 (summer peak focus)
    - Geography: Houston metropolitan area and surrounding counties
    - Refresh Rate: AMI data refreshes every 15 minutes
    
    ## Boundaries
    You do NOT have access to:
    - Billing or payment information
    - Customer contracts or legal documents
    - Real-time SCADA data
    - Employee information
    
    If asked about these topics, politely explain you don't have access.
    
  response: |
    Be specific and include actual numbers, dates, and identifiers in responses.
    Use appropriate units: kWh for energy, kVA for transformer capacity, % for utilization.
    Keep responses concise but complete.
    
  orchestration: |
    Use the Analyst tool for all structured data queries about:
    - Energy consumption and usage patterns
    - Transformer loading and health metrics
    - Customer counts and segmentation
    - Aggregations, trends, and comparisons

tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: Analyst
      description: |
        Converts natural language questions to SQL queries against the utility semantic model.
        Use for questions about energy consumption, transformer health, customer data, 
        and any analytical queries requiring aggregation or comparison.

tool_resources:
  Analyst:
    semantic_view: <% database %>.APPLICATIONS.UTILITY_SEMANTIC_VIEW
$$;

-- -----------------------------------------------------------------------------
-- 2. GRANT AGENT ACCESS
-- -----------------------------------------------------------------------------

GRANT USAGE ON AGENT GRID_INTELLIGENCE_AGENT 
    TO ROLE IDENTIFIER('<% user_role %>');

-- -----------------------------------------------------------------------------
-- 3. VERIFICATION
-- -----------------------------------------------------------------------------

-- Show agent was created
SHOW AGENTS IN SCHEMA APPLICATIONS;

-- Describe agent configuration
DESCRIBE AGENT GRID_INTELLIGENCE_AGENT;

SELECT 'Agent GRID_INTELLIGENCE_AGENT created successfully' AS STATUS;
SELECT 'To use: Access via Snowsight Intelligence or REST API at /api/agents' AS USAGE_NOTE;

-- =============================================================================
-- DEPLOYMENT COMPLETE
--
-- To interact with the agent:
--   1. Snowsight: Go to Snowflake Intelligence > Select GRID_INTELLIGENCE_AGENT
--   2. REST API: POST /api/agents/GRID_INTELLIGENCE_AGENT/conversations
--
-- Example API call:
--   curl -X POST "https://<account>.snowflakecomputing.com/api/agents/<db>.<schema>.GRID_INTELLIGENCE_AGENT/conversations" \
--     -H "Authorization: Bearer <token>" \
--     -H "Content-Type: application/json" \
--     -d '{"messages": [{"role": "user", "content": "What is the total energy consumption?"}]}'
--
-- Next: Run 11_ml_feature_tables.sql to create ML training data
-- =============================================================================
