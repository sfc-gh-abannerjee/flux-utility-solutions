-- =============================================================================
-- 10_cortex_agent.sql
-- Flux Utility Solutions - Grid Intelligence Cortex Agent
-- =============================================================================
-- Purpose: Create or update the Cortex Agent for natural language grid analytics
-- Dependencies: 08_semantic_view.sql, 09_cortex_search_services.sql
--
-- Variable Templating (Snow CLI Jinja2):
--   <% database %>   - Target database name (e.g., FLUX_DB)
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
--   - "comment" is NOT valid inside the spec $$ block — use SET COMMENT separately
--   - Generic tools require input_schema even for no-arg functions (properties: {})
--   - Use plain $$ delimiter (NOT tagged dollar-quotes like $$spec$$)
--
-- WHAT THIS CREATES/UPDATES:
--   A 9-tool Cortex Agent (ALTER AGENT MODIFY LIVE VERSION — in-place update):
--     1. grid_analyst        - Cortex Analyst text-to-SQL (semantic view)
--     2. search_customers    - Customer profile search (686K profiles)
--     3. search_meters       - AMI meter metadata search (597K meters)
--     4. search_technical_docs  - Internal tech-docs quick-reference (pre-loaded)
--     5. search_compliance_docs - NERC/regulatory compliance docs
--     6. search_outages      - 18K+ historical outage events (incl. Beryl 2024)
--     7. search_pdf_docs     - S3 PDF corpus (earnings, ESG, manuals, standards)
--     8. parse_document      - On-the-fly AI_PARSE_DOCUMENT + AI_COMPLETE
--     9. list_pdf_files      - Directory listing SP for @UTILITY_PDF_STAGE (LIST_PDF_DOCS_PROC)
--
-- NOTE: Service names must match those created in 09_cortex_search_services.sql
--
-- DEPLOYMENT NOTE (REV4-01):
--   This script uses ALTER AGENT MODIFY LIVE VERSION SET SPECIFICATION to update
--   the live agent in place. It does NOT use CREATE OR REPLACE AGENT, which would
--   destroy the agent identity and all version history. For a net-new deployment
--   (first run against a fresh database), create the agent manually first or use
--   the CREATE AGENT block at the bottom of this file (commented out).
-- =============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE WAREHOUSE IDENTIFIER('<% warehouse %>');
USE SCHEMA APPLICATIONS;

-- -----------------------------------------------------------------------------
-- 1. UPDATE CORTEX AGENT (in-place, preserves created_on and version history)
-- -----------------------------------------------------------------------------
-- Uses ALTER AGENT MODIFY LIVE VERSION SET SPECIFICATION to update the live
-- agent spec without recreating it. This preserves the agent identity,
-- created_on timestamp, and any aliased versions.
--
-- Key requirements:
--   - models.orchestration: The LLM to use (e.g., claude-sonnet-4-5)
--   - tools[].tool_spec.type: Must match valid tool types
--   - tool_resources: Must reference valid semantic views or search services

ALTER AGENT GRID_INTELLIGENCE_AGENT MODIFY LIVE VERSION SET SPECIFICATION = $$
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
    | Outage History | 18,689 events | July 2024 (incl. Hurricane Beryl 2024-07-08) |
    
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
    | "outage", "outages", "power outage", "Beryl", "storm impact" | search_outages | Outage history search |
    | "outages by cause", "outage trends", "customers affected" | grid_analyst | Aggregate outage queries via semantic view |
    | "List PDFs", "What PDFs do you have", "Which files are available" | list_pdf_files | Returns directory listing of @UTILITY_PDF_STAGE — call BEFORE parse_document if filename unknown |
    | "Search PDF docs", "What does the manual/report say about X", "find in the technical PDFs" | search_pdf_docs | Indexed Cortex Search over S3 PDF corpus (NERC, IEEE, ERCOT, FluxCo manuals, earnings reports) |
    | "Read [exact_filename].pdf", "Open the file X and summarize", "Extract from [filename]" | parse_document | On-the-fly AI_PARSE_DOCUMENT + AI_COMPLETE — slower, costs more, use only when user names a specific file |
    
    ### Multi-Tool Queries
    
    Some questions require multiple tools:
    1. "Find John Smith and show his usage" → search_customers → grid_analyst
    2. "Which overloaded transformers need maintenance?" → grid_analyst → search_technical_docs
    3. "What NERC standards apply to overloaded transformers?" → grid_analyst → search_compliance_docs
    4. "Show outage history for transformer TRF-10042 and its load data" → search_outages → grid_analyst
    
    ### Search Routing Precedence
    
    When a user asks a technical, procedural, or narrative question: (1) call
    grid_analyst for any structured data, (2) call search_pdf_docs for
    narrative/standard/manual content, (3) call parse_document ONLY if the user
    named a specific file OR search_pdf_docs returned nothing relevant. Never
    call parse_document without first knowing the filename — call list_pdf_files
    if uncertain. AI_PARSE_DOCUMENT reads bytes from AWS S3
    (s3://<your-pdf-bucket>/raw/pdfs/) on every call — this proves data
    unification across Snowflake-internal and external-stage sources.
    
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
        Search the curated FluxCo internal technical-docs knowledge base —
        pre-loaded equipment summaries and quick-reference cards. Best for
        high-level definitional lookups. For specific manuals, regulatory
        standards, financial reports, or strategic documents prefer
        `search_pdf_docs`.
  - tool_spec:
      type: cortex_search
      name: search_compliance_docs
      description: >
        Search NERC and regulatory compliance documents including TPL-001,
        FAC-003, EOP-011, CIP standards, and internal utility policies.
  - tool_spec:
      type: cortex_search
      name: search_outages
      description: >
        Search 18K+ historical outage events by cause, location, time window,
        or notes. Use for outage history, storm impact analysis
        (Hurricane Beryl 2024-07-08), customer disruption queries, and
        root-cause investigation.
  - tool_spec:
      type: cortex_search
      name: search_pdf_docs
      description: >
        Search the full-text S3-ingested utility-grid technical PDF corpus —
        earnings reports, ESG reports, board strategy memos, hydrogen + battery
        storage studies, NERC standards, ERCOT operations references, Texas hail
        incident report, and more. Best for narrative content, manuals, regulatory
        citations, financial reports. The corpus lives on AWS S3 and is searched
        via Cortex Search over chunked text. Always prefer this over
        `search_technical_docs` when the user asks for a specific manual,
        standard, or report.
  - tool_spec:
      type: generic
      name: parse_document
      description: >
        Extract text and answer a specific question from a named PDF in the
        document stage. Use ONLY when the user names a specific PDF file or you
        have already discovered the filename via list_pdf_files. Reads bytes from
        AWS S3 in real time via AI_PARSE_DOCUMENT(LAYOUT) — demonstrates
        external-stage data extraction.
      input_schema:
        type: object
        properties:
          file_path:
            type: string
            description: "Relative PDF filename, e.g. 'Hydrogen_Strategy_Report.pdf'"
          question:
            type: string
            description: "Specific question to answer from the document content (max 1000 chars)"
        required:
          - file_path
          - question
  - tool_spec:
      type: generic
      name: list_pdf_files
      description: >
        List all PDFs available in the document stage. Returns relative_path,
        size_bytes, last_modified for each PDF. Call BEFORE parse_document when
        the user asks 'what PDFs are available' or you don't already know an
        exact filename.
      input_schema:
        type: object
        properties: {}

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
  search_outages:
    search_service: "<% database %>.APPLICATIONS.OUTAGE_HISTORY_SEARCH"
    max_results: 10
    id_column: OUTAGE_ID
    title_column: OUTAGE_ID
  search_pdf_docs:
    search_service: "<% database %>.APPLICATIONS.UTILITY_PDF_DOCS_SEARCH"
    max_results: 5
    id_column: CHUNK_ID
    title_column: DOCUMENT_TITLE
  parse_document:
    identifier: "<% database %>.APPLICATIONS.PARSE_AND_EXTRACT"
    type: procedure
    execution_environment:
      type: warehouse
      warehouse: "<% warehouse %>"
  list_pdf_files:
    identifier: "<% database %>.APPLICATIONS.LIST_PDF_DOCS_PROC"
    type: procedure
    execution_environment:
      type: warehouse
      warehouse: "<% warehouse %>"
$$;

-- Update the human-readable comment separately (not part of spec)
ALTER AGENT GRID_INTELLIGENCE_AGENT SET COMMENT = 'Grid Intelligence Agent - 9-tool utility operations assistant: semantic SQL, customer/meter/outage search, technical/compliance docs, S3 PDF search + on-the-fly parse + list (Phase 3b)';

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
GRANT USAGE ON CORTEX SEARCH SERVICE <% database %>.APPLICATIONS.OUTAGE_HISTORY_SEARCH
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');
GRANT USAGE ON CORTEX SEARCH SERVICE <% database %>.APPLICATIONS.UTILITY_PDF_DOCS_SEARCH
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');

-- Grant access to generic tool procedures/functions
GRANT USAGE ON PROCEDURE <% database %>.APPLICATIONS.PARSE_AND_EXTRACT(STRING, STRING)
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');
GRANT USAGE ON PROCEDURE <% database %>.APPLICATIONS.LIST_PDF_DOCS_PROC()
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');

-- Grant access to semantic view for Cortex Analyst
GRANT SELECT ON SEMANTIC VIEW <% database %>.APPLICATIONS.UTILITY_SEMANTIC_VIEW
    TO ROLE IDENTIFIER('<% user_role | default("PUBLIC") %>');

-- -----------------------------------------------------------------------------
-- 3. VERIFICATION
-- -----------------------------------------------------------------------------

-- Show agent was updated
SHOW AGENTS IN SCHEMA APPLICATIONS;

-- Describe agent configuration
DESCRIBE AGENT GRID_INTELLIGENCE_AGENT;

SELECT 'Agent GRID_INTELLIGENCE_AGENT updated successfully with 9 tools' AS STATUS;

-- =============================================================================
-- DEPLOYMENT COMPLETE
--
-- Tools available:
--   1. grid_analyst        - Cortex Analyst text-to-SQL (semantic view)
--   2. search_customers    - Customer profile search (686K profiles)
--   3. search_meters       - AMI meter metadata search (597K meters)
--   4. search_technical_docs  - Internal tech-docs quick-reference
--   5. search_compliance_docs - NERC/regulatory compliance docs
--   6. search_outages      - Historical outage events (18K+, incl. Beryl)
--   7. search_pdf_docs     - S3 PDF corpus Cortex Search
--   8. parse_document      - On-the-fly AI_PARSE_DOCUMENT + AI_COMPLETE
--   9. list_pdf_files      - Directory listing SP for @UTILITY_PDF_STAGE (LIST_PDF_DOCS_PROC)
--
-- Invocation methods:
--   1. SQL: SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('DB.SCHEMA.AGENT', $$...$$)
--   2. Snowsight: Go to Snowflake Intelligence > Select GRID_INTELLIGENCE_AGENT
--   3. REST API: POST /api/agents/<db>.<schema>.GRID_INTELLIGENCE_AGENT/conversations
--
-- Next: Run 11_ml_feature_tables.sql to create ML training data
--
-- NET-NEW DEPLOYMENT NOTE:
-- If deploying to a fresh database where the agent does not exist yet,
-- first create it with a minimal spec, then re-run this script:
--
--   CREATE AGENT GRID_INTELLIGENCE_AGENT FROM SPECIFICATION $$
--   models:
--     orchestration: claude-sonnet-4-5
--   tools: []
--   tool_resources: {}
--   $$;
-- =============================================================================
