# Flux Utility Solutions - Cortex Guide

Setup and configuration guide for Cortex Analyst, Search, and Agents.

## Overview

Flux uses three Cortex AI services:

| Service | Purpose | Data |
|---------|---------|------|
| Cortex Analyst | SQL generation from natural language | Semantic view |
| Cortex Search | RAG for unstructured lookup | Customer, meter, docs |
| Cortex Agent | Orchestrated AI assistant | All tools |

## Cortex Analyst

### Semantic View

The semantic view enables natural language queries over structured data.

**Deploy:**
```sql
CREATE OR ALTER SEMANTIC VIEW APPLICATIONS.UTILITY_SEMANTIC_VIEW
COMMENT = 'Utility analytics semantic model'
AS $$ <yaml content> $$;
```

**Components:**
- 30 tables with metadata
- Dimensions, facts, metrics
- Named filters
- Verified queries
- Relationships between tables

### Best Practices

1. **Use descriptive synonyms** - Help the LLM understand user intent
```yaml
- name: METER_ID
  synonyms: [meter, meter_number, smart_meter]
```

2. **Add sample values** - Ground the model in real data
```yaml
sample_values: ['XFMR-00001', 'XFMR-91456']
```

3. **Define metrics** - Pre-calculate common aggregations
```yaml
metrics:
  - name: TOTAL_CONSUMPTION
    expr: SUM(USAGE_KWH_ADJUSTED)
```

4. **Create filters** - Simplify common WHERE clauses
```yaml
filters:
  - name: SUMMER_2025
    expr: TIMESTAMP BETWEEN '2025-07-01' AND '2025-08-31'
```

5. **Verify queries** - Test and document working SQL
```yaml
verified_queries:
  - name: top_consumers
    question: "Who are the top 10 customers by usage?"
    sql: |
      SELECT ... ORDER BY usage DESC LIMIT 10
```

### Owner's Rights

Semantic views use **owner's rights** - users don't need direct table access:

```sql
-- User role only needs semantic view access
GRANT SELECT ON SEMANTIC VIEW UTILITY_SEMANTIC_VIEW 
    TO ROLE FLUX_USER_ROLE;

-- No need to grant SELECT on underlying tables!
```

## Cortex Search

### Services

**Customer Search** (686K records)
```sql
CREATE OR ALTER CORTEX SEARCH SERVICE CUSTOMER_SEARCH_SERVICE
    ON SEARCH_TEXT
    ATTRIBUTES CUSTOMER_SEGMENT, CITY, ACCOUNT_STATUS
    WAREHOUSE = SI_DEMO_WH
    TARGET_LAG = '1 day'
AS (
    SELECT 
        CUSTOMER_ID,
        FULL_NAME,
        CONCAT(FULL_NAME, ' ', CITY, ' ', CUSTOMER_SEGMENT) AS SEARCH_TEXT
    FROM CUSTOMERS_MASTER_DATA
);
```

**Meter Search** (597K records)
```sql
CREATE OR ALTER CORTEX SEARCH SERVICE AMI_METADATA_SEARCH
    ON SEARCH_TEXT
    ATTRIBUTES CITY, TRANSFORMER_ID
    WAREHOUSE = SI_DEMO_WH
    TARGET_LAG = '1 hour'
AS (
    SELECT 
        METER_ID,
        TRANSFORMER_ID,
        CONCAT(METER_ID, ' ', CITY, ' ', TRANSFORMER_ID) AS SEARCH_TEXT
    FROM METER_INFRASTRUCTURE
);
```

### Query Search

```sql
-- Preview search results
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'APPLICATIONS.CUSTOMER_SEARCH_SERVICE',
    '{
        "query": "residential customer Houston",
        "columns": ["CUSTOMER_ID", "FULL_NAME", "CITY"],
        "limit": 5
    }'
);
```

### Best Practices

1. **Choose search columns carefully** - Concatenate relevant text
2. **Set appropriate attributes** - Enable filtering
3. **Use reasonable TARGET_LAG** - Balance freshness vs. cost
4. **Include identifiers** - Return IDs for follow-up queries

## Cortex Agents

### Grid Intelligence Agent

Main agent for utility analytics:

```sql
CREATE OR ALTER AGENT GRID_INTELLIGENCE_AGENT
    MODEL = 'auto'
    TOOLS = (
        CORTEX_ANALYST(
            SEMANTIC_VIEW => 'APPLICATIONS.UTILITY_SEMANTIC_VIEW'
        ),
        CORTEX_SEARCH(
            SEARCH_SERVICE => 'APPLICATIONS.CUSTOMER_SEARCH_SERVICE'
        ),
        CORTEX_SEARCH(
            SEARCH_SERVICE => 'APPLICATIONS.AMI_METADATA_SEARCH'
        )
    )
    INSTRUCTIONS = $$ <instructions> $$;
```

### 4-Layer Instruction Pattern

1. **Data Layer** - What data is available
```
## Available Data
- AMI Readings: 7.1B rows, 15-min intervals
- Transformers: 91K assets with health scores
- Customers: 686K profiles
```

2. **Orchestration Layer** - Tool selection logic
```
## Tool Selection
| Question Type | Tool |
|---------------|------|
| Aggregations | Cortex Analyst |
| Customer lookup | Customer Search |
| Technical docs | Technical Search |
```

3. **Response Layer** - Output formatting
```
## Response Guidelines
- Use tables for rankings
- Include specific numbers
- Cite data sources
```

4. **Tool Descriptions** - Clear tool purpose
```
## Tools
- utility_analytics: Query structured data
- customer_search: Find customer profiles
```

### Testing Agents

```sql
-- Test via SQL
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'AGENT:APPLICATIONS.GRID_INTELLIGENCE_AGENT',
    'What transformers are at highest risk of failure?'
);
```

Or use Snowsight → Cortex AI → Agents

## Troubleshooting

### "Semantic view not responding"
- Check warehouse is running
- Verify semantic view deployed correctly
- Test with simple query first

### "Search service not ready"
- Wait for initial index build (can take minutes)
- Check TARGET_LAG setting
- Verify source query returns data

### "Agent tool selection wrong"
- Improve tool descriptions
- Add explicit selection logic in instructions
- Include example questions per tool

### "SQL generation incorrect"
- Add verified queries for similar patterns
- Improve dimension/metric descriptions
- Add more synonyms

## Performance

| Operation | Expected Time |
|-----------|---------------|
| Semantic view query | 2-10 seconds |
| Search query | <1 second |
| Agent response | 5-15 seconds |
| Search index refresh | Minutes |

## Monitoring

```sql
-- Search service status
SHOW CORTEX SEARCH SERVICES IN SCHEMA APPLICATIONS;

-- Agent usage (via account usage)
SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_TEXT LIKE '%CORTEX%'
ORDER BY START_TIME DESC
LIMIT 100;
```
