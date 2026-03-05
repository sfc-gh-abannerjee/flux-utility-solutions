-- =============================================================================
-- 10_cortex_agent.sql
-- Flux Utility Solutions - Grid Intelligence Cortex Agent
-- =============================================================================
-- Purpose: Create Cortex Agent for natural language grid analytics
-- Dependencies: 08_semantic_view.sql, 09_cortex_search_services.sql
--
-- Variable Templating (Snow CLI Jinja2):
--   <% database %>   - Target database name (e.g., FLUX_DEMO)
--   <% warehouse %>  - Warehouse for agent execution
--   <% user_role %>  - Role to grant agent usage (default: PUBLIC)
--
-- Usage:
--   snow sql -f scripts/10_cortex_agent.sql \
--       -D "database=YOUR_DATABASE" -D "warehouse=YOUR_WH" -D "user_role=PUBLIC"
--
-- IMPORTANT YAML format notes (discovered via testing):
--   - Tool type for Cortex Analyst must be "cortex_analyst_text_to_sql" (NOT "cortex_analyst")
--   - Analyst tool_resources must include execution_environment with type + warehouse
--   - Search tool_resources use "search_service" key (NOT "name")
--   - max_results should be an integer (not a quoted string)
--
-- WHAT THIS CREATES:
--   A 5-tool Cortex Agent:
--     1. grid_analyst        - Cortex Analyst text-to-SQL (semantic view)
--     2. search_customers    - Customer profile search (686K profiles)
--     3. search_meters       - AMI meter metadata search (597K meters)
--     4. search_technical_docs  - Technical manuals RAG (20K chunks)
--     5. search_compliance_docs - NERC/regulatory compliance docs
--
-- NOTE: Service names must match those created in 09_cortex_search_services.sql
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE WAREHOUSE IDENTIFIER('<% warehouse %>');
USE SCHEMA APPLICATIONS;

-- -----------------------------------------------------------------------------
-- 1. CREATE CORTEX AGENT
-- -----------------------------------------------------------------------------
-- Uses FROM SPECIFICATION with YAML to define the agent's tools, instructions,
-- and resource bindings. The agent orchestrates between Cortex Analyst (text-to-SQL
-- via semantic view), customer/meter search, technical docs, and compliance docs.
--
-- Key requirements:
--   - models.orchestration: The LLM to use (e.g., claude-sonnet-4-5)
--   - tools[].tool_spec.type: Must match valid tool types
--   - tool_resources: Must reference valid semantic views or search services

CREATE OR REPLACE AGENT GRID_INTELLIGENCE_AGENT
    COMMENT = 'Grid Intelligence Agent - 5-tool utility operations assistant with semantic SQL, customer/meter search, technical docs, and compliance RAG'
    FROM SPECIFICATION $$
models:
  orchestration: claude-sonnet-4-5

orchestration:
  budget:
    seconds: 180
    tokens: 100000

instructions:
  system: |
    ## Layer 1: Identity and Data Context
    
    You are the **Grid Intelligence Assistant**, a specialized AI assistant for 
    GridStar Energy utility grid operations. You help operations personnel, 
    engineers, and analysts understand grid performance.
    
    ### Data Available
    
    | Dataset | Scale | Coverage |
    |---------|-------|----------|
    | AMI Readings | 7.1B rows | Jul-Aug 2024, Jul-Aug 2025 |
    | Transformers | 91K assets | Full fleet |
    | Transformer Load | 211M rows | Summer peak hours |
    | Customers | 686K profiles | All segments |
    | Meters | 597K devices | All active meters |
    | Substations | 98 | Distribution network |
    | Circuits | 73 | All feeders |
    
    ### Data Characteristics
    
    - **Time Focus**: Data covers SUMMER PEAK periods (July-August)
    - **Geography**: Houston metropolitan area and surrounding counties
    - **Refresh Rate**: AMI data at 15-minute intervals
    - **Completeness**: ~98% meter reporting rate during normal operations
    
  orchestration: |
    ## Layer 2: Tool Selection
    
    Select tools based on question type:
    
    | Question Pattern | Tool | Examples |
    |-----------------|------|----------|
    | "How much...", "Total...", "Average..." | grid_analyst | Consumption totals, averages |
    | "Top 10...", "Highest...", "Lowest..." | grid_analyst | Rankings, extremes |
    | "Trend...", "Over time...", "Compare..." | grid_analyst | Time series, YoY |
    | "Which transformers...", "Overloaded..." | grid_analyst | Asset queries |
    | "Find customer...", "Who is..." | search_customers | Customer lookup |
    | "Meter MTR-...", "Meters on transformer..." | search_meters | Meter lookup |
    | "How do I...", "What causes...", "Maintenance..." | search_technical_docs | Procedures |
    | "NERC standard...", "Compliance...", "Regulatory..." | search_compliance_docs | Regulations |
    
    ### Multi-Tool Queries
    
    Some questions require multiple tools:
    1. "Find John Smith and show his usage" → search_customers → grid_analyst
    2. "Which overloaded transformers need maintenance?" → grid_analyst → search_technical_docs
    3. "What NERC standards apply to overloaded transformers?" → grid_analyst → search_compliance_docs
    
  response: |
    ## Layer 3: Response Guidelines
    
    - Use tables for rankings and comparisons
    - Include specific numbers, not vague descriptions
    - Show units (kWh, kVA, %, degrees F)
    - Reference time periods for context
    - When citing compliance requirements, include the specific standard number (e.g., TPL-001-5)
    - For technical issues, include relevant equipment identifiers and procedures
    
    ## Layer 4: Scope and Boundaries
    
    You CAN answer questions about:
    - Energy consumption patterns and trends
    - Transformer health, loading, thermal stress
    - Customer lookup and service information
    - Grid operations and circuit status
    - Technical procedures and maintenance
    - NERC and regulatory compliance standards
    - Outage patterns and voltage quality
    
    You CANNOT access:
    - Billing or payment information
    - Customer contracts or legal documents
    - Real-time SCADA data
    - Employee or HR information
    - Financial or budgeting data
    
    If asked about unavailable topics, politely explain you don't have access.

tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: grid_analyst
      description: >
        Query structured utility data including AMI meter readings, transformer
        health metrics, customer profiles, and load analysis via natural language.
        Use for aggregations, trends, comparisons, rankings, and time-series analysis.
  - tool_spec:
      type: cortex_search
      name: search_customers
      description: >
        Search 686K customer profiles by name, address, city, county, ZIP code,
        or customer segment. Use for finding specific customers or account lookups.
  - tool_spec:
      type: cortex_search
      name: search_meters
      description: >
        Search 597K smart meters by meter ID, location (city, ZIP, county),
        associated transformer, or customer segment. Use for meter lookups.
  - tool_spec:
      type: cortex_search
      name: search_technical_docs
      description: >
        Search technical manuals, equipment documentation, maintenance procedures,
        and troubleshooting guides. Use for technical questions and procedures.
  - tool_spec:
      type: cortex_search
      name: search_compliance_docs
      description: >
        Search NERC and regulatory compliance documents including TPL-001,
        FAC-003, EOP-011, CIP standards, and internal utility policies.

tool_resources:
  grid_analyst:
    semantic_view: "<% database %>.APPLICATIONS.UTILITY_SEMANTIC_VIEW"
    execution_environment:
      type: warehouse
      warehouse: "<% warehouse %>"
  search_customers:
    search_service: "<% database %>.APPLICATIONS.CUSTOMER_SEARCH_SERVICE"
    max_results: 5
    id_column: CUSTOMER_ID
    title_column: FULL_NAME
  search_meters:
    search_service: "<% database %>.APPLICATIONS.AMI_METADATA_SEARCH"
    max_results: 5
    id_column: METER_ID
    title_column: METER_ID
  search_technical_docs:
    search_service: "<% database %>.PRODUCTION.TECHNICAL_DOCS_SEARCH"
    max_results: 5
    id_column: CHUNK_ID
    title_column: DOCUMENT_TYPE
  search_compliance_docs:
    search_service: "<% database %>.ML_DEMO.COMPLIANCE_DOCS_SEARCH"
    max_results: 5
    id_column: DOC_ID
    title_column: TITLE
$$;

-- -----------------------------------------------------------------------------
-- 2. GRANT AGENT ACCESS
-- -----------------------------------------------------------------------------

GRANT USAGE ON AGENT GRID_INTELLIGENCE_AGENT 
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');

-- Grant access to underlying search services (agent needs these at runtime)
GRANT USAGE ON CORTEX SEARCH SERVICE <% database %>.APPLICATIONS.CUSTOMER_SEARCH_SERVICE
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');
GRANT USAGE ON CORTEX SEARCH SERVICE <% database %>.APPLICATIONS.AMI_METADATA_SEARCH
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');
GRANT USAGE ON CORTEX SEARCH SERVICE <% database %>.PRODUCTION.TECHNICAL_DOCS_SEARCH
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');
GRANT USAGE ON CORTEX SEARCH SERVICE <% database %>.ML_DEMO.COMPLIANCE_DOCS_SEARCH
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');

-- Grant access to semantic view for Cortex Analyst
GRANT SELECT ON SEMANTIC VIEW <% database %>.APPLICATIONS.UTILITY_SEMANTIC_VIEW
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');

-- -----------------------------------------------------------------------------
-- 3. VERIFICATION
-- -----------------------------------------------------------------------------

-- Show agent was created
SHOW AGENTS IN SCHEMA APPLICATIONS;

-- Describe agent configuration
DESCRIBE AGENT GRID_INTELLIGENCE_AGENT;

SELECT 'Agent GRID_INTELLIGENCE_AGENT created successfully with 5 tools' AS STATUS;

-- =============================================================================
-- DEPLOYMENT COMPLETE
--
-- Tools available:
--   1. grid_analyst        - Cortex Analyst text-to-SQL (semantic view)
--   2. search_customers    - Customer profile search (686K profiles)
--   3. search_meters       - AMI meter metadata search (597K meters)
--   4. search_technical_docs  - Technical manuals RAG (20K chunks)
--   5. search_compliance_docs - NERC/regulatory compliance docs
--
-- Invocation methods:
--   1. SQL: SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('DB.SCHEMA.AGENT', $$...$$)
--   2. Snowsight: Go to Snowflake Intelligence > Select GRID_INTELLIGENCE_AGENT
--   3. REST API: POST /api/agents/<db>.<schema>.GRID_INTELLIGENCE_AGENT/conversations
--
-- Next: Run 11_ml_feature_tables.sql to create ML training data
-- =============================================================================
