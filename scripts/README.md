# Flux Utility Solutions - SQL Scripts

Deploy Flux infrastructure using Snow CLI with variable templating.

## Important: Variable Syntax

These scripts use **Snow CLI Jinja2 templating** with `<% variable %>` syntax.

```sql
-- Example from scripts
CREATE DATABASE IF NOT EXISTS IDENTIFIER('<% database %>');
USE WAREHOUSE IDENTIFIER('<% warehouse %>');
```

**This is NOT the same as:**
- Snowflake session variables (`$variable`) used in Notebooks
- Standard Jinja2 (`{{ variable }}`) used elsewhere
- EXECUTE IMMEDIATE FROM (`$variable` from USING clause)

## Prerequisites

1. **Snow CLI** (Snowflake CLI)
   ```bash
   # Install via pip
   pip install snowflake-cli
   
   # Or via pipx (recommended)
   pipx install snowflake-cli
   ```

2. **Configure a connection**
   ```bash
   snow connection add
   # Follow prompts to create a connection
   
   # List connections
   snow connection list
   ```

## Quick Start

Deploy a minimal environment in under 2 minutes:

```bash
# Navigate to scripts directory
cd scripts

# Deploy database and warehouses
snow sql -f 01_database_infrastructure.sql \
    -D "database=FLUX_DEV" \
    -D "admin_role=ACCOUNTADMIN" \
    -D "user_role=PUBLIC" \
    -c your_connection_name

snow sql -f 02_warehouses.sql \
    -D "database=FLUX_DEV" \
    -D "warehouse=FLUX_DEV_WH" \
    -D "warehouse_size=XSMALL" \
    -c your_connection_name

# Deploy core tables
snow sql -f 03_substations_transformers.sql \
    -D "database=FLUX_DEV" \
    -D "warehouse=FLUX_DEV_WH" \
    -c your_connection_name
```

## Script Reference

### Infrastructure (Run First)

| Script | Description | Required Variables |
|--------|-------------|-------------------|
| `01_database_infrastructure.sql` | Database, schemas, roles | `database`, `admin_role`, `user_role` |
| `02_warehouses.sql` | Warehouses (primary, large, loading, cortex) | `database`, `warehouse`, `warehouse_size` |

### Core Tables

| Script | Description | Required Variables |
|--------|-------------|-------------------|
| `03_substations_transformers.sql` | Substations and transformers | `database`, `warehouse` |
| `04_meters_infrastructure.sql` | Meters and service points | `database`, `warehouse` |
| `05_customers_master.sql` | Customer master data | `database`, `warehouse` |
| `06_ami_readings_pipeline.sql` | AMI time-series tables | `database`, `warehouse` |
| `07_aggregation_tables.sql` | Aggregation views and tables | `database`, `warehouse` |

### Cortex AI (Optional)

| Script | Description | Required Variables |
|--------|-------------|-------------------|
| `08_semantic_view.sql` | Semantic view for Cortex Analyst | `database`, `warehouse` |
| `09_cortex_search_services.sql` | Cortex Search services | `database`, `warehouse` |
| `10_cortex_agent.sql` | Cortex Agent configuration | `database`, `warehouse` |

### Advanced Features

| Script | Description | Required Variables |
|--------|-------------|-------------------|
| `11_ml_feature_tables.sql` | ML feature engineering | `database`, `warehouse` |
| `12_postgres_instance.sql` | PostgreSQL integration | `database`, `warehouse` |
| `13_spcs_compute.sql` | Snowpark Container Services | `database`, `warehouse` |
| `14_geospatial_functions.sql` | Geospatial UDFs | `database`, `warehouse` |

### Data Loading

| Script | Description | Required Variables |
|--------|-------------|-------------------|
| `50_load_seed_data.sql` | Load sample seed data | `database`, `warehouse` |
| `51_generate_ami_sample.sql` | Generate synthetic AMI data | `database`, `warehouse` |

## Variable Reference

| Variable | Description | Example Values |
|----------|-------------|----------------|
| `database` | Target database name | `FLUX_DEV`, `FLUX_PROD` |
| `warehouse` | Primary warehouse | `FLUX_DEV_WH` |
| `warehouse_size` | Warehouse size | `XSMALL`, `SMALL`, `MEDIUM` |
| `admin_role` | Administrative role | `FLUX_DEV_ADMIN`, `ACCOUNTADMIN` |
| `user_role` | User role | `FLUX_DEV_USER`, `PUBLIC` |

## Full Deployment Example

```bash
# Set your connection
export CONN="your_connection_name"
export DB="FLUX_DEV"
export WH="FLUX_DEV_WH"

# Infrastructure
snow sql -c $CONN -f 01_database_infrastructure.sql \
    -D "database=$DB" -D "admin_role=FLUX_DEV_ADMIN" -D "user_role=FLUX_DEV_USER"

snow sql -c $CONN -f 02_warehouses.sql \
    -D "database=$DB" -D "warehouse=$WH" -D "warehouse_size=SMALL"

# Core tables (run in order)
for script in 03 04 05 06 07; do
    snow sql -c $CONN -f ${script}_*.sql -D "database=$DB" -D "warehouse=$WH"
done

# Cortex AI (optional)
for script in 08 09 10; do
    snow sql -c $CONN -f ${script}_*.sql -D "database=$DB" -D "warehouse=$WH"
done

# Validation
snow sql -c $CONN -f 99_validate_deployment.sql -D "database=$DB" -D "warehouse=$WH"
```

## Troubleshooting

### "Variable is undefined"
Ensure all required `-D` flags are passed:
```bash
# Wrong - missing warehouse_size
snow sql -f 02_warehouses.sql -D "database=FLUX_DEV"

# Correct
snow sql -f 02_warehouses.sql -D "database=FLUX_DEV" -D "warehouse=FLUX_DEV_WH" -D "warehouse_size=SMALL"
```

### "Role is a system object"
System roles (ACCOUNTADMIN, PUBLIC, SYSADMIN) cannot be granted to other roles. The scripts handle this automatically by checking role names before granting.

### "IDENTIFIER() doesn't support concatenation"
Use explicit variable names instead of string concatenation:
```sql
-- Won't work
CREATE WAREHOUSE IDENTIFIER($prefix || '_WH');

-- Works
SET wh_name = 'FLUX_DEV_WH';
CREATE WAREHOUSE IDENTIFIER($wh_name);
```

## See Also

- [CLI Quick Start](../cli/README.md) - Automated deployment with quickstart.sh
- [Terraform](../terraform/README.md) - Infrastructure as Code approach
- [Notebooks](../notebooks/README.md) - Interactive notebook deployment
