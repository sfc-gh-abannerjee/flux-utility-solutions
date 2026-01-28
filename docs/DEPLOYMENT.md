# Flux Utility Solutions - Deployment Guide

Complete guide for deploying Flux across all 5 paths.

## Prerequisites

### Snowflake Account
- Account with ACCOUNTADMIN or equivalent role
- Sufficient warehouse credits
- Access to create databases, schemas, warehouses

### Tools (by path)
| Path | Required Tools |
|------|----------------|
| SQL Scripts | Snowsight or Snow CLI |
| Notebooks | Snowsight Notebooks |
| Git Integration | Git repository access |
| CLI | Python 3.9+, Snow CLI |
| Terraform | Terraform 1.0+, Snowflake provider |

## Path 1: SQL Scripts

Recommended for: Manual deployment, testing, learning

### Quick Start

```bash
# Clone repository
git clone https://github.com/Snowflake-Labs/flux-utility-solutions.git
cd flux-utility-solutions

# Edit configuration
vim scripts/config.yaml

# Run scripts in order (via Snowsight)
# 1. Open each .sql file
# 2. Replace {{ variables }} with values from config.yaml
# 3. Execute
```

### Script Execution Order

| # | Script | Purpose |
|---|--------|---------|
| 01 | database_infrastructure.sql | Database, schemas, roles |
| 02 | warehouses.sql | Warehouse configuration |
| 03 | substations_transformers.sql | Grid topology tables |
| 04 | meters_infrastructure.sql | Meter and pole tables |
| 05 | customers_master.sql | Customer master data |
| 06 | ami_readings_pipeline.sql | AMI tables and dynamic tables |
| 07 | aggregation_tables.sql | Hourly aggregations |
| 08 | semantic_view.sql | Cortex Analyst semantic view |
| 09 | cortex_search_services.sql | Search services |
| 10 | cortex_agent.sql | Grid Intelligence Agent |
| 11-15 | (optional) | ML, PostgreSQL, SPCS, Geo, Marketplace |
| 16 | rbac_final.sql | Complete RBAC setup |
| 17 | validation_queries.sql | Validate deployment |

### Configuration

Edit `scripts/config.yaml`:

```yaml
prod:
  database: FLUX_PROD
  warehouse: FLUX_PROD_WH
  warehouse_size: MEDIUM
  admin_role: FLUX_PROD_ADMIN
  user_role: FLUX_PROD_USER
```

## Path 2: Snowflake Notebooks

Recommended for: Interactive deployment, exploration

### Steps

1. Open Snowsight → Projects → Notebooks
2. Import notebooks from `notebooks/` directory
3. Set variables at top of each notebook
4. Run cells sequentially

### Notebooks

| Notebook | Purpose |
|----------|---------|
| 01_deploy_infrastructure.sql | Database, schemas, warehouses |
| explore_ami_data.sql | Data exploration |
| analysis_transformer_risk.sql | Risk analysis |

## Path 3: Git Integration (EXECUTE IMMEDIATE FROM)

Recommended for: Version-controlled, CI/CD deployment

### Setup

```sql
-- Create Git integration
CREATE OR REPLACE API INTEGRATION flux_git_integration
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/Snowflake-Labs/')
    ENABLED = TRUE;

-- Create Git repository
CREATE OR REPLACE GIT REPOSITORY flux_solutions_repo
    API_INTEGRATION = flux_git_integration
    ORIGIN = 'https://github.com/Snowflake-Labs/flux-utility-solutions.git';

-- Fetch latest
ALTER GIT REPOSITORY flux_solutions_repo FETCH;
```

### Deploy from Git

```sql
-- Execute script with variable substitution
EXECUTE IMMEDIATE FROM @flux_solutions_repo/branches/main/scripts/01_database_infrastructure.sql
USING (
    database => 'FLUX_PROD',
    warehouse => 'FLUX_PROD_WH',
    admin_role => 'FLUX_PROD_ADMIN',
    user_role => 'FLUX_PROD_USER'
);
```

### Full Deployment

```sql
CALL DEPLOY_ALL_FROM_GIT('main', 'prod', FALSE);
```

## Path 4: CLI Automation

Recommended for: Automation, scripting, batch operations

### Setup

```bash
pip install snowflake-cli pyyaml
snow connection add --connection-name flux_conn
```

### Deploy

```bash
# Dry run
python cli/deploy.py --env prod --all --dry-run

# Deploy all scripts
python cli/deploy.py --env prod --all

# Deploy specific scripts
python cli/deploy.py --env prod --scripts 01-10

# Validate
python cli/validate.py --env prod --check all
```

## Path 5: Terraform

Recommended for: Infrastructure as Code, enterprise deployment

### Setup

```bash
cd terraform
terraform init
```

### Deploy

```bash
# Plan
terraform plan -var-file="environments/prod.tfvars"

# Apply
terraform apply -var-file="environments/prod.tfvars"

# Note: Cortex components require SQL scripts
```

### Terraform Manages
- ✅ Database and schemas
- ✅ Warehouses
- ✅ Roles and grants
- ✅ Compute pools
- ❌ Semantic views (use SQL)
- ❌ Cortex Search (use SQL)
- ❌ Cortex Agents (use SQL)

## Post-Deployment

### Validation

```sql
-- Run validation queries
CALL DEPLOY_FLUX_SOLUTION('prod', 17, 17, FALSE, FALSE);
```

### Verify Components

```sql
-- Check tables
SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_SCHEMA = 'PRODUCTION';

-- Check semantic view
SHOW SEMANTIC VIEWS IN SCHEMA APPLICATIONS;

-- Check search services
SHOW CORTEX SEARCH SERVICES IN SCHEMA APPLICATIONS;

-- Check agent
SHOW AGENTS IN SCHEMA APPLICATIONS;
```

## Environment Matrix

| Environment | Database | Primary WH | Use Case |
|-------------|----------|------------|----------|
| dev | FLUX_DEV | XSMALL | Development |
| staging | FLUX_STAGING | SMALL | Testing |
| prod | FLUX_PROD | MEDIUM | Production |
| si_demos | SI_DEMOS | SI_DEMO_WH | Demos |

## Troubleshooting

### Common Issues

**"Insufficient privileges"**
- Ensure running with ACCOUNTADMIN or admin role
- Check future grants are set up

**"Object does not exist"**
- Run scripts in order (dependencies)
- Verify database/schema context

**"Search service not ready"**
- Wait for index build (can take minutes)
- Check warehouse is running

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for more.
