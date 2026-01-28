-- =============================================================================
-- 10_cortex_agent.sql
-- Flux Utility Solutions - Grid Intelligence Cortex Agent
-- =============================================================================
-- Purpose: Create Cortex Agent for natural language grid analytics
-- Dependencies: 08_semantic_view.sql, 09_cortex_search_services.sql
-- Jinja2 Variables:
--   {{ database }}  - Target database name
--
-- Note: Full agent spec is in agents/grid_intelligence_agent.yaml
-- =============================================================================

USE DATABASE IDENTIFIER('{{ database }}');
USE SCHEMA APPLICATIONS;

-- -----------------------------------------------------------------------------
-- 1. CREATE CORTEX AGENT
-- -----------------------------------------------------------------------------
-- Following Snowflake best practices for agent design:
-- - Narrow scope (utility grid analytics only)
-- - Explicit tool selection logic
-- - Clear boundaries and limitations

CREATE OR ALTER AGENT GRID_INTELLIGENCE_AGENT
    COMMENT = 'Grid Intelligence Agent - Utility operations assistant for AMI analytics, transformer health, and customer lookup'
    -- Model selection: 'auto' for automatic best model selection
    MODEL = 'auto'
    -- Tool configuration
    TOOLS = (
        -- Cortex Analyst for structured data queries
        CORTEX_ANALYST(
            SEMANTIC_VIEW => '{{ database }}.APPLICATIONS.UTILITY_SEMANTIC_VIEW'
        ),
        -- Cortex Search for customer lookup
        CORTEX_SEARCH(
            SEARCH_SERVICE => '{{ database }}.APPLICATIONS.CUSTOMER_SEARCH_SERVICE'
        ),
        -- Cortex Search for meter lookup
        CORTEX_SEARCH(
            SEARCH_SERVICE => '{{ database }}.APPLICATIONS.AMI_METADATA_SEARCH'
        ),
        -- Cortex Search for technical documentation
        CORTEX_SEARCH(
            SEARCH_SERVICE => '{{ database }}.APPLICATIONS.TECHNICAL_MANUALS_SEARCH_SERVICE'
        )
    )
    -- Agent instructions (orchestration layer)
    INSTRUCTIONS = $$
## Identity and Purpose

You are the **Grid Intelligence Assistant**, a specialized AI assistant for utility grid operations. You help operations personnel, engineers, and analysts understand grid performance, customer usage patterns, and asset health.

## Scope

You are authorized to answer questions about:
- **AMI Data**: Energy consumption, voltage readings, meter performance (7.1B+ readings)
- **Transformer Health**: Load factors, thermal stress, overloading risk (91K assets)
- **Customer Information**: Account lookup, segmentation, service addresses (686K customers)
- **Grid Operations**: Circuit status, outage patterns, load analysis
- **Technical Documentation**: Transformer manuals, troubleshooting guides

## Tool Selection Guidelines

Use these tools based on the question type:

| Question Type | Tool | Examples |
|---------------|------|----------|
| Consumption analytics | Cortex Analyst (UTILITY_SEMANTIC_VIEW) | "Top 10 customers by usage", "Monthly trends" |
| Transformer analysis | Cortex Analyst (UTILITY_SEMANTIC_VIEW) | "Overloaded transformers", "High-risk assets" |
| Customer lookup | Cortex Search (CUSTOMER_SEARCH_SERVICE) | "Find John Smith", "Customers in 77001" |
| Meter lookup | Cortex Search (AMI_METADATA_SEARCH) | "Meter MTR-00012345", "Meters on XFMR-001" |
| Technical questions | Cortex Search (TECHNICAL_MANUALS_SEARCH_SERVICE) | "Transformer maintenance", "Voltage sag causes" |

## Data Context

- **Time Range**: Data primarily covers July-August 2024 and July-August 2025 (summer peak focus)
- **Geography**: Houston metropolitan area and surrounding counties
- **Refresh Rate**: AMI data refreshes every 15 minutes; search indexes daily

## Response Guidelines

1. **Be specific**: Include actual numbers, dates, and identifiers in responses
2. **Cite sources**: Reference which table or service provided the data
3. **Acknowledge limits**: If data isn't available, clearly state why
4. **Use appropriate units**: kWh for energy, kVA for transformer capacity, % for utilization

## Boundaries

You do NOT have access to:
- Billing or payment information
- Customer contracts or legal documents
- Real-time SCADA data (use PostgreSQL API for real-time)
- Employee information

If asked about these topics, respond: "I don't have access to [topic]. Please contact [appropriate department]."
$$;

-- -----------------------------------------------------------------------------
-- 2. CREATE CASCADE ANALYSIS TOOL (Custom Procedure)
-- -----------------------------------------------------------------------------
-- Custom tool for cascade failure simulation

CREATE OR REPLACE PROCEDURE CASCADE_FAILURE_SIMULATION(
    PATIENT_ZERO VARCHAR,
    MAX_WAVES NUMBER DEFAULT 5
)
RETURNS TABLE (
    WAVE NUMBER,
    ASSET_ID VARCHAR,
    ASSET_TYPE VARCHAR,
    FAILURE_PROBABILITY NUMBER,
    AFFECTED_CUSTOMERS NUMBER
)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'networkx')
HANDLER = 'run_simulation'
COMMENT = 'Simulates cascade failure propagation from a patient zero node'
AS
$$
def run_simulation(session, patient_zero: str, max_waves: int):
    import networkx as nx
    
    # Build network graph from topology
    topology_df = session.sql('''
        SELECT from_asset_id, to_asset_id, connection_type, impedance
        FROM ''' + session.get_current_database() + '''.PRODUCTION.GRID_TOPOLOGY
    ''').collect()
    
    G = nx.Graph()
    for row in topology_df:
        G.add_edge(row['FROM_ASSET_ID'], row['TO_ASSET_ID'], 
                   weight=row['IMPEDANCE'] if row['IMPEDANCE'] else 1.0)
    
    # BFS cascade simulation
    results = []
    visited = set([patient_zero])
    current_wave = [(patient_zero, 0)]
    
    for wave in range(max_waves):
        next_wave = []
        for node, _ in current_wave:
            if node in G:
                for neighbor in G.neighbors(node):
                    if neighbor not in visited:
                        visited.add(neighbor)
                        # Calculate failure probability based on distance
                        prob = max(0.1, 1.0 - (wave * 0.2))
                        results.append({
                            'WAVE': wave + 1,
                            'ASSET_ID': neighbor,
                            'ASSET_TYPE': 'TRANSFORMER' if 'XFMR' in neighbor else 'SUBSTATION',
                            'FAILURE_PROBABILITY': prob,
                            'AFFECTED_CUSTOMERS': 0  # Would lookup from data
                        })
                        next_wave.append((neighbor, wave + 1))
        current_wave = next_wave
        if not current_wave:
            break
    
    return session.create_dataframe(results)
$$;

-- Grant execute to admin role
GRANT USAGE ON PROCEDURE CASCADE_FAILURE_SIMULATION(VARCHAR, NUMBER) 
    TO ROLE IDENTIFIER('{{ admin_role }}');

-- -----------------------------------------------------------------------------
-- 3. GRANT AGENT ACCESS
-- -----------------------------------------------------------------------------

GRANT USAGE ON AGENT GRID_INTELLIGENCE_AGENT 
    TO ROLE IDENTIFIER('{{ user_role }}');

-- -----------------------------------------------------------------------------
-- 4. VERIFICATION
-- -----------------------------------------------------------------------------

-- Show agent
SHOW AGENTS IN SCHEMA APPLICATIONS;

-- Test agent (basic query)
-- Note: Full testing should be done via Snowflake Intelligence UI or API
SELECT 'Agent GRID_INTELLIGENCE_AGENT created successfully' as STATUS;

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- Next: Run 11_ml_feature_tables.sql to create ML training data
-- =============================================================================
