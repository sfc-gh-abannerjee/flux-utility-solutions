-- =============================================================================
-- 09_agent_alter_outage_tool.sql
-- Flux Utility Solutions — Add search_outages tool to GRID_INTELLIGENCE_AGENT
-- =============================================================================
-- Purpose: ALTER (not DROP/REPLACE) the live GIA to add the search_outages
--          cortex_search tool backed by OUTAGE_HISTORY_SEARCH service.
--          Also extends orchestration instructions with outage routing rows.
--
-- IMPORTANT: tools array is a full-replace in ALTER AGENT MODIFY LIVE VERSION.
--            This spec includes ALL 6 tools (5 original + search_outages).
--
-- Prerequisites:
--   - 07_outage_semantic_view.sql deployed (OUTAGE_HISTORY_SEARCHABLE view)
--   - 08_outage_history_search.sql deployed (OUTAGE_HISTORY_SEARCH CSS)
--
-- Usage:
--   snow sql -f scripts/realistic_data/09_agent_alter_outage_tool.sql \
--       --connection se_demo
--
-- Rollback: git revert to previous spec or use ALTER AGENT with 5-tool spec
-- =============================================================================

USE DATABASE FLUX_DB;
USE SCHEMA APPLICATIONS;

-- Confirm CSS exists before altering agent
SHOW CORTEX SEARCH SERVICES IN SCHEMA APPLICATIONS
    LIKE 'OUTAGE_HISTORY_SEARCH';

-- ALTER AGENT: add search_outages as 6th tool.
-- The specification below is the COMPLETE merged 6-tool spec.
ALTER AGENT FLUX_DB.APPLICATIONS.GRID_INTELLIGENCE_AGENT MODIFY LIVE VERSION SET
SPECIFICATION = $spec$
{
  "models": {
    "orchestration": "claude-sonnet-4-5"
  },
  "orchestration": {
    "budget": {
      "seconds": 180,
      "tokens": 100000
    }
  },
  "instructions": {
    "system": "## Layer 1: Identity and Data Context\n\nYou are the **Grid Intelligence Assistant**, a specialized AI assistant for \nGridStar Energy utility grid operations. You help operations personnel, \nengineers, and analysts understand grid performance.\n\n### Data Available\n\n| Dataset | Scale | Coverage |\n|---------|-------|----------|\n| AMI Readings | 7.1B rows | Jul-Aug 2024, Jul-Aug 2025 |\n| Transformers | 91K assets | Full fleet |\n| Transformer Load | 211M rows | Summer peak hours |\n| Customers | 686K profiles | All segments |\n| Meters | 597K devices | All active meters |\n| Substations | 98 | Distribution network |\n| Circuits | 73 | All feeders |\n| Outage History | 18,689 events | July 2024 (incl. Hurricane Beryl 2024-07-08) |\n\n### Data Characteristics\n\n- **Time Focus**: Data covers SUMMER PEAK periods (July-August)\n- **Geography**: Houston metropolitan area and surrounding counties\n- **Refresh Rate**: AMI data at 15-minute intervals\n- **Completeness**: ~98% meter reporting rate during normal operations\n",
    "orchestration": "## Layer 2: Tool Selection\n\nSelect tools based on question type:\n\n| Question Pattern | Tool | Examples |\n|-----------------|------|----------|\n| \"How much...\", \"Total...\", \"Average...\" | grid_analyst | Consumption totals, averages |\n| \"Top 10...\", \"Highest...\", \"Lowest...\" | grid_analyst | Rankings, extremes |\n| \"Trend...\", \"Over time...\", \"Compare...\" | grid_analyst | Time series, YoY |\n| \"Which transformers...\", \"Overloaded...\" | grid_analyst | Asset queries |\n| \"Find customer...\", \"Who is...\" | search_customers | Customer lookup |\n| \"Meter MTR-...\", \"Meters on transformer...\" | search_meters | Meter lookup |\n| \"How do I...\", \"What causes...\", \"Maintenance...\" | search_technical_docs | Procedures |\n| \"NERC standard...\", \"Compliance...\", \"Regulatory...\" | search_compliance_docs | Regulations |\n| \"outage\", \"outages\", \"power outage\", \"Beryl\", \"storm impact\" | search_outages | Outage history search |\n| \"outages by cause\", \"outage trends\", \"customers affected\" | grid_analyst | Aggregate outage queries via semantic view |\n\n### Multi-Tool Queries\n\nSome questions require multiple tools:\n1. \"Find John Smith and show his usage\" \u2192 search_customers \u2192 grid_analyst\n2. \"Which overloaded transformers need maintenance?\" \u2192 grid_analyst \u2192 search_technical_docs\n3. \"What NERC standards apply to overloaded transformers?\" \u2192 grid_analyst \u2192 search_compliance_docs\n4. \"Show outage history for transformer TRF-10042 and its load data\" \u2192 search_outages \u2192 grid_analyst\n",
    "response": "## Layer 3: Response Guidelines\n\n- Use tables for rankings and comparisons\n- Include specific numbers, not vague descriptions\n- Show units (kWh, kVA, %, degrees F)\n- Reference time periods for context\n- When citing compliance requirements, include the specific standard number (e.g., TPL-001-5)\n- For technical issues, include relevant equipment identifiers and procedures\n\n## Layer 4: Scope and Boundaries\n\nYou CAN answer questions about:\n- Energy consumption patterns and trends\n- Transformer health, loading, thermal stress\n- Customer lookup and service information\n- Grid operations and circuit status\n- Technical procedures and maintenance\n- NERC and regulatory compliance standards\n- Outage patterns and voltage quality\n\nYou CANNOT access:\n- Billing or payment information\n- Customer contracts or legal documents\n- Real-time SCADA data\n- Employee or HR information\n- Financial or budgeting data\n\nIf asked about unavailable topics, politely explain you don't have access.\n"
  },
  "tools": [
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "grid_analyst",
        "description": "Query structured utility data including AMI meter readings, transformer health metrics, customer profiles, and load analysis via natural language. Use for aggregations, trends, comparisons, rankings, and time-series analysis.\n"
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "search_customers",
        "description": "Search 686K customer profiles by name, address, city, county, ZIP code, or customer segment. Use for finding specific customers or account lookups.\n"
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "search_meters",
        "description": "Search 597K smart meters by meter ID, location (city, ZIP, county), associated transformer, or customer segment. Use for meter lookups.\n"
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "search_technical_docs",
        "description": "Search technical manuals, equipment documentation, maintenance procedures, and troubleshooting guides. Use for technical questions and procedures.\n"
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "search_compliance_docs",
        "description": "Search NERC and regulatory compliance documents including TPL-001, FAC-003, EOP-011, CIP standards, and internal utility policies.\n"
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "search_outages",
        "description": "Search 18K+ historical outage events by cause, location, time window, or notes. Use for outage history, storm impact analysis (Hurricane Beryl 2024-07-08), customer disruption queries, and root-cause investigation.\n"
      }
    }
  ],
  "tool_resources": {
    "grid_analyst": {
      "semantic_view": "FLUX_DB.APPLICATIONS.UTILITY_SEMANTIC_VIEW",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "FLUX_WH"
      }
    },
    "search_customers": {
      "search_service": "FLUX_DB.APPLICATIONS.CUSTOMER_SEARCH_SERVICE",
      "max_results": 5,
      "id_column": "CUSTOMER_ID",
      "title_column": "FULL_NAME"
    },
    "search_meters": {
      "search_service": "FLUX_DB.APPLICATIONS.AMI_METADATA_SEARCH",
      "max_results": 5,
      "id_column": "METER_ID",
      "title_column": "METER_ID"
    },
    "search_technical_docs": {
      "search_service": "FLUX_DB.PRODUCTION.TECHNICAL_DOCS_SEARCH",
      "max_results": 5,
      "id_column": "CHUNK_ID",
      "title_column": "DOCUMENT_TYPE"
    },
    "search_compliance_docs": {
      "search_service": "FLUX_DB.ML_DEMO.COMPLIANCE_DOCS_SEARCH",
      "max_results": 5,
      "id_column": "DOC_ID",
      "title_column": "TITLE"
    },
    "search_outages": {
      "search_service": "FLUX_DB.APPLICATIONS.OUTAGE_HISTORY_SEARCH",
      "max_results": 10,
      "id_column": "OUTAGE_ID",
      "title_column": "OUTAGE_ID"
    }
  }
}
$spec$;

-- Verify: expect 6 tools in agent_spec JSON
DESCRIBE AGENT FLUX_DB.APPLICATIONS.GRID_INTELLIGENCE_AGENT;

-- =============================================================================
-- END
-- After this step, run C4 sanity checks:
--   1. DESCRIBE AGENT → confirm 6 tools in agent_spec
--   2. SEARCH_PREVIEW for "Beryl impact" → returns WEATHER outages
--   3. Semantic view query for WEATHER outages 2024-07-08..2024-07-15
-- =============================================================================
