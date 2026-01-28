# Flux Utility Solutions - Semantic Models

This directory contains semantic model YAML files for Cortex Analyst.

## Files

| File | Description |
|------|-------------|
| `utility_semantic_model.yaml` | Complete 30-table semantic model for utility analytics |
| `transformer_semantic_model.yaml` | Focused model for transformer health analysis |
| `customer_semantic_model.yaml` | Customer segmentation and consumption model |

## Usage

### Deploy via SQL Script (Path 1)

The semantic model is deployed automatically by `scripts/08_semantic_view.sql`.

### Deploy Directly with YAML

```sql
-- Create semantic view from YAML file
CREATE OR ALTER SEMANTIC VIEW {{ database }}.APPLICATIONS.UTILITY_SEMANTIC_VIEW
    YAML_FILE = '@STAGE_NAME/models/utility_semantic_model.yaml';
```

### Jinja2 Variables

All models use these variables for environment portability:

| Variable | Description | Example |
|----------|-------------|---------|
| `{{ database }}` | Target database name | `FLUX_PROD` |
| `{{ schema }}` | Schema name | `PRODUCTION` |

## Model Structure

### Tables Covered

1. **AMI Data**
   - `AMI_READINGS_ENHANCED` - 7.1B interval readings
   - `AMI_MONTHLY_USAGE` - Monthly aggregates
   - `AMI_CUSTOMER_MONTHLY` - Customer-level monthly data

2. **Customers**
   - `CUSTOMERS_MASTER_DATA` - 686K customer profiles
   - `CUSTOMER_SEGMENT_CONFIG` - Segment definitions
   - `ENERGY_BURDEN_ANALYSIS` - Income-energy analysis

3. **Transformers**
   - `TRANSFORMER_METADATA` - 91K transformer assets
   - `TRANSFORMER_HOURLY_LOAD` - 211M hourly load records
   - `TRANSFORMER_THERMAL_STRESS_MATERIALIZED` - Stress analysis

4. **Grid Infrastructure**
   - `SUBSTATIONS` - 98 substations
   - `CIRCUIT_METADATA` - 73 distribution circuits
   - `METER_INFRASTRUCTURE` - 597K meters
   - `GRID_POLES_INFRASTRUCTURE` - 1.2M poles

5. **Operations**
   - `SAP_WORK_ORDERS` - 250K work orders
   - `OUTAGE_EVENTS` - Outage tracking
   - `WEATHER_HOURLY` - Weather data

6. **External Data**
   - `ERCOT_LOAD_UNIFIED` - Grid load data
   - `CIRCUIT_VEGETATION_RISK` - Tree proximity risk

### Verified Queries

Each model includes verified queries for common analytics patterns:
- Top consumers by usage
- High-risk transformers
- Monthly usage trends
- Outage impact analysis
- Energy burden by segment

## Best Practices

1. **Owner's Rights**: Semantic views use owner's rights - the executing user doesn't need direct table access
2. **Future Grants**: Always add future grants for new semantic views
3. **Synonyms**: Add synonyms for natural language query flexibility
4. **Filters**: Define named filters for common WHERE clause patterns
5. **Metrics**: Pre-define aggregations for consistent calculations
