# Flux Utility Solutions - Notebooks

Snowflake Notebooks for deployment, exploration, and analysis.

## Important: Variable Syntax

Notebooks use **Snowflake session variables** with `$variable` syntax:

```sql
-- Set variables at the start of the notebook
SET database = 'FLUX_DEV';
SET warehouse_prefix = 'FLUX_DEV';

-- Use with IDENTIFIER() function
USE DATABASE IDENTIFIER($database);
CREATE WAREHOUSE IF NOT EXISTS IDENTIFIER($wh_primary);
```

**This is NOT the same as:**
- Snow CLI Jinja2 (`<% variable %>`) used in `/scripts/`
- Standard Jinja2 (`{{ variable }}`) 
- EXECUTE IMMEDIATE FROM USING clause

### IDENTIFIER() Limitation

`IDENTIFIER()` does **NOT** support string concatenation:

```sql
-- This WILL NOT work:
CREATE WAREHOUSE IDENTIFIER($prefix || '_WH');

-- This WORKS - use explicit variables:
SET wh_primary = 'FLUX_DEV_WH';
CREATE WAREHOUSE IF NOT EXISTS IDENTIFIER($wh_primary);
```

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

1. Open Snowsight -> Projects -> Notebooks
2. Click "+" -> "Import from File"
3. Select notebook `.sql` file
4. Choose database/schema/warehouse
5. **Edit the SET statements** at the top to match your environment

### Run from Snowsight

1. After import, click "Run All" or run cells individually
2. Variables are set via `SET` statements in the first cell
3. Modify variable values before running to customize deployment

## Customizing Variables

Edit the configuration cell at the top of each notebook:

```sql
-- =============================================================================
-- CONFIGURATION - Edit these values for your environment
-- =============================================================================
SET database = 'MY_DATABASE';           -- Your target database
SET warehouse_prefix = 'MY_PREFIX';     -- Prefix for warehouse names
SET admin_role = 'MY_ADMIN_ROLE';       -- Admin role (or ACCOUNTADMIN)
SET user_role = 'MY_USER_ROLE';         -- User role (or PUBLIC)
```

## See Also

- [Scripts](../scripts/README.md) - Snow CLI deployment with Jinja2 templating
- [CLI Quick Start](../cli/README.md) - Automated deployment
- [Terraform](../terraform/README.md) - Infrastructure as Code
