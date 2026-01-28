# Flux Utility Solutions - Notebooks

Snowflake Notebooks for deployment, exploration, and analysis.

## Notebook Format

Notebooks use Snowflake's native `.sql` format with markdown cells.

```sql
-- ## Markdown Header
-- Regular markdown text
-- 
-- - Bullet points
-- - More points

-- Cell divider
SELECT * FROM table;
```

## Available Notebooks

### Deployment

| Notebook | Description |
|----------|-------------|
| `01_deploy_infrastructure.sql` | Deploy databases, schemas, warehouses, roles |
| `02_deploy_tables.sql` | Create production tables |
| `03_deploy_cortex.sql` | Deploy semantic view, search, agents |

### Exploration

| Notebook | Description |
|----------|-------------|
| `explore_ami_data.sql` | Explore 7.1B AMI readings |
| `explore_transformers.sql` | Transformer fleet analysis |
| `explore_customers.sql` | Customer segmentation analysis |

### Analysis

| Notebook | Description |
|----------|-------------|
| `analysis_peak_demand.sql` | Summer peak demand patterns |
| `analysis_transformer_risk.sql` | Transformer failure risk |
| `analysis_energy_burden.sql` | Energy burden by income segment |

## Usage

### Import to Snowsight

1. Open Snowsight → Projects → Notebooks
2. Click "+" → "Import from File"
3. Select notebook `.sql` file
4. Choose database/schema/warehouse

### Execute from SQL

```sql
EXECUTE IMMEDIATE FROM '@STAGE/notebooks/01_deploy_infrastructure.sql'
USING (database => 'FLUX_DEV', warehouse => 'SI_DEMO_WH');
```

## Variables

All notebooks support Jinja2 variables:

| Variable | Description |
|----------|-------------|
| `{{ database }}` | Target database |
| `{{ warehouse }}` | Warehouse to use |
| `{{ admin_role }}` | Admin role |
| `{{ user_role }}` | User role |
