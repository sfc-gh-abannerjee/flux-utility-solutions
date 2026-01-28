# Flux Utility Solutions - Cortex Agents

This directory contains agent configurations for Snowflake Cortex Agents.

## Files

| File | Description |
|------|-------------|
| `grid_intelligence_agent.yaml` | Main Grid Intelligence Agent configuration |
| `transformer_analyst_agent.yaml` | Specialized agent for transformer health |
| `customer_service_agent.yaml` | Customer lookup and service agent |

## Architecture

### 4-Layer Agent Instruction Pattern

All agents follow Snowflake's recommended 4-layer instruction pattern:

1. **Data Layer**: Available tables, relationships, and data characteristics
2. **Orchestration Layer**: Tool selection logic and workflow coordination  
3. **Response Layer**: Output formatting and communication guidelines
4. **Tool Descriptions**: Clear descriptions for each available tool

### Tool Configuration

Agents can use these tool types:

| Tool Type | Usage |
|-----------|-------|
| `CORTEX_ANALYST` | Structured data queries via semantic views |
| `CORTEX_SEARCH` | Unstructured data retrieval (RAG) |
| `SNOWFLAKE_FUNCTION` | Custom UDFs and procedures |
| `WEB_SEARCH` | External web search (if enabled) |

## Deployment

### Via SQL Script (Path 1)

Agents are deployed by `scripts/10_cortex_agent.sql`.

### Direct SQL

```sql
CREATE OR ALTER AGENT {{ database }}.APPLICATIONS.GRID_INTELLIGENCE_AGENT
    MODEL = 'auto'
    TOOLS = (
        CORTEX_ANALYST(SEMANTIC_VIEW => '{{ database }}.APPLICATIONS.UTILITY_SEMANTIC_VIEW'),
        CORTEX_SEARCH(SEARCH_SERVICE => '{{ database }}.APPLICATIONS.CUSTOMER_SEARCH_SERVICE')
    )
    INSTRUCTIONS = $$ <agent instructions> $$;
```

## Best Practices

### Narrow Scope
Each agent should have a well-defined domain. Don't create "do everything" agents.

### Explicit Tool Selection
Include clear guidance on which tool to use for each question type.

### Acknowledge Limitations
Agents should clearly state what they cannot do or don't have access to.

### Response Guidelines
Define output format expectations (tables, bullet points, specific units).

## Testing

Test agents via Snowflake Intelligence UI or programmatically:

```sql
-- Test agent
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'AGENT:{{ database }}.APPLICATIONS.GRID_INTELLIGENCE_AGENT',
    'What transformers are at risk of failure?'
);
```
