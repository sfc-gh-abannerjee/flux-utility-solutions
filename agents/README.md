# Flux Utility Solutions - Cortex Agents

This directory contains agent configurations for Snowflake Cortex Agents.

## Files

| File | Description |
|------|-------------|
| `grid_intelligence_agent.yaml` | Main Grid Intelligence Agent - reference YAML spec |

> **Note:** The YAML file is the reference specification. The actual deployment is
> done by `scripts/10_cortex_agent.sql` which embeds the spec inline via
> `CREATE OR REPLACE AGENT ... FROM SPECIFICATION $$ <yaml> $$`.

## Architecture

### 4-Layer Agent Instruction Pattern

All agents follow Snowflake's recommended 4-layer instruction pattern:

1. **Data Layer**: Available tables, relationships, and data characteristics
2. **Orchestration Layer**: Tool selection logic and workflow coordination  
3. **Response Layer**: Output formatting and communication guidelines
4. **Tool Descriptions**: Clear descriptions for each available tool

### Tool Configuration

The Grid Intelligence Agent uses 4 tools:

| Tool Name | Type | Purpose |
|-----------|------|---------|
| `Analyst` | `cortex_analyst_text_to_sql` | Structured data queries via semantic view |
| `search_customers` | `cortex_search` | Customer lookup by name, address, account |
| `search_meters` | `cortex_search` | Meter/AMI device search |
| `search_technical_docs` | `cortex_search` | Technical manual RAG retrieval |

Each tool has a corresponding `tool_resources` entry that specifies the Snowflake
object (semantic view or search service) and search parameters (max_results,
id_column, title_column).

## Deployment

Agents are deployed by `scripts/10_cortex_agent.sql`:

```bash
snow sql -f scripts/10_cortex_agent.sql \
    -D "database=FLUX_DB" -D "user_role=PUBLIC" \
    -c your_connection_name
```

### IMPORTANT - Common pitfalls

- **Do NOT add `sample_questions`** to the YAML spec. It is not a valid field
  and will cause a deployment error.
- **Model name**: The orchestration model is set to `claude-sonnet-4-5`. Check
  Snowflake docs for currently available models if you want to change it.
- **Search services must exist first**: Run `09_cortex_search_services.sql`
  before `10_cortex_agent.sql`, or the agent will fail to create because it
  references search services that do not exist.

## Best Practices

### Narrow Scope
Each agent should have a well-defined domain. The Grid Intelligence Agent
covers grid operations, customer lookup, and technical documentation.

### Explicit Tool Selection
The orchestration instructions include clear guidance on which tool to use
for each question type (SQL for metrics, search for lookups, etc.).

### Acknowledge Limitations
Agents should clearly state what they cannot do or access.

### Response Guidelines
Define output format expectations (tables, bullet points, specific units).

## Testing

Test agents via the Snowflake Intelligence UI (Snowsight) or via the REST API:

```
POST /api/v2/databases/{db}/schemas/APPLICATIONS/agents/GRID_INTELLIGENCE_AGENT:run
```

> **Note:** There is no `SNOWFLAKE.CORTEX.INVOKE_AGENT()` SQL function. Agents
> are invoked via the REST API or the Snowsight UI, not via SQL.
