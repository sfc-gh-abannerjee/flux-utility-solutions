# Flux Utility Solutions - Deployment Path Comparison Report

## Executive Summary

This report compares the five deployment paths against the SI_DEMOS production baseline. Each path has been validated with step-by-step validation scripts.

| Path | Status | Validation Script | Objects Created |
|------|--------|-------------------|-----------------|
| SQL Scripts | ✅ Ready | `scripts/validate/*.sql` | Full infrastructure |
| Git Integration | ✅ Ready | `git_deploy/validate_git_deployment.sql` | Full infrastructure |
| CLI Shell | ✅ Ready | `cli/validate_cli_deployment.sh` | Full infrastructure |
| Terraform | ✅ Ready | `terraform/validate_terraform.sh` | Infrastructure + roles |
| Notebooks | ✅ Ready | Manual validation | Demo-ready subset |

---

## Production Baseline (SI_DEMOS)

### PRODUCTION Schema
| Object Type | Count | Key Objects |
|-------------|-------|-------------|
| Tables | 114 | SUBSTATIONS, TRANSFORMER_METADATA, METER_INFRASTRUCTURE, CUSTOMERS_MASTER_DATA, AMI_INTERVAL_READINGS, TRANSFORMER_HOURLY_LOAD |
| Views | 33 | Analytical views, dashboard views |
| Row Count | 7.1B+ | AMI_INTERVAL_READINGS dominates |

### APPLICATIONS Schema
| Object Type | Count | Key Objects |
|-------------|-------|-------------|
| Objects | 50 | Semantic views, Cortex Search services, Agents, Stages |

---

## Path 1: SQL Scripts (`scripts/`)

### Deployment Command
```bash
# Full deployment with variable substitution
snow sql -f scripts/01_database_infrastructure.sql -D "database='FLUX_PROD'" -D "warehouse='FLUX_WH'"
# ... continue for scripts 02-10
```

### Validation
```bash
# Step-by-step validation
./scripts/validate/validate_sql_deployment.sh FLUX_PROD

# Or individual step validation
snow sql -f scripts/validate/01_validate_infrastructure.sql -D "database='FLUX_PROD'"
```

### Objects Created
| Script | Objects |
|--------|---------|
| 01_database_infrastructure | Database, 5 schemas, roles, grants |
| 02_warehouses | Warehouses (primary, large, cortex) |
| 03_substations_transformers | SUBSTATIONS, TRANSFORMER_METADATA, CIRCUIT_METADATA |
| 04_meters_infrastructure | METER_INFRASTRUCTURE |
| 05_customers_master | CUSTOMERS_MASTER_DATA |
| 06_ami_readings_pipeline | AMI_INTERVAL_READINGS, AMI_MONTHLY_USAGE |
| 07_aggregation_tables | TRANSFORMER_HOURLY_LOAD, OUTAGE_EVENTS, VOLTAGE_SAG_EVENTS |
| 08_semantic_view | UTILITY_SEMANTIC_VIEW |
| 09_cortex_search_services | Search services |
| 10_cortex_agent | GRID_INTELLIGENCE_AGENT |

---

## Path 2: Git Integration (`git_deploy/`)

### Setup (One-time)
```sql
-- Create integration
CREATE OR REPLACE API INTEGRATION github_api_integration
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/Snowflake-Labs')
  ENABLED = TRUE;

-- Create repository reference
CREATE OR REPLACE GIT REPOSITORY flux_utility_solutions_repo
  API_INTEGRATION = github_api_integration
  ORIGIN = 'https://github.com/Snowflake-Labs/flux-utility-solutions.git';

ALTER GIT REPOSITORY flux_utility_solutions_repo FETCH;
```

### Deployment Command
```sql
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/git_deploy/deploy_from_git.sql
  USING (
    database => 'FLUX_PROD',
    warehouse => 'FLUX_WH',
    admin_role => 'ACCOUNTADMIN',
    user_role => 'PUBLIC'
  );
```

### Validation
```sql
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/git_deploy/validate_git_deployment.sql
  USING (database => 'FLUX_PROD');
```

### Objects Created
Same as SQL Scripts path - executes same underlying scripts.

---

## Path 3: CLI Shell (`cli/`)

### Deployment Commands
```bash
# Quick start (15 minutes, demo-ready)
./cli/quickstart.sh --connection myconn

# Full deployment
./cli/deploy.sh --env dev --connection myconn

# Production deployment
./cli/deploy.sh --env prod --connection prod_admin
```

### Validation
```bash
# Bash validation
./cli/validate_cli_deployment.sh FLUX_DEV myconn

# Python validation (full)
python cli/validate.py --env dev --check all --connection myconn
```

### Objects Created
| Quickstart | Full Deploy |
|------------|-------------|
| Database + schemas | Database + schemas |
| Core tables | Core tables |
| AMI tables | AMI tables |
| Cortex services | Cortex services |
| - | PostgreSQL instance |
| - | SPCS application |
| - | ML pipelines |

---

## Path 4: Terraform (`terraform/`)

### Deployment Commands
```bash
cd terraform
terraform init
terraform plan -var-file="environments/dev.tfvars"
terraform apply -var-file="environments/dev.tfvars"
```

### Validation
```bash
./terraform/validate_terraform.sh dev
./terraform/validate_terraform.sh dev --plan  # Requires credentials
```

### Objects Created (Terraform-managed)
| Resource | Description |
|----------|-------------|
| Database | FLUX_DEV (or per environment) |
| Schemas | PRODUCTION, APPLICATIONS, SECRETS |
| Roles | Admin, User, Analyst, ETL, Service |
| Warehouses | Primary, Large, Loading, Cortex |
| Compute Pool | (if SPCS enabled) |

### Post-Terraform Steps
Tables and Cortex services require SQL scripts (not Terraform-managed):
```bash
# After terraform apply, run SQL scripts
snow sql -f scripts/03_substations_transformers.sql -D "database='FLUX_DEV'"
# ... continue with remaining scripts
```

---

## Path 5: Notebooks (`notebooks/`)

### Deployment
Upload notebooks to Snowsight and run interactively:
1. `notebooks/setup/01_full_deployment.ipynb` - Complete setup notebook
2. `notebooks/demos/*.ipynb` - Demo notebooks

### Validation
Manual validation through notebook outputs.

---

## Comparison Matrix

| Feature | SQL Scripts | Git Integration | CLI Shell | Terraform | Notebooks |
|---------|-------------|-----------------|-----------|-----------|-----------|
| **Automation Level** | Manual | Automated | Automated | IaC | Interactive |
| **Prerequisites** | Snow CLI | ACCOUNTADMIN | Snow CLI | Terraform | Snowsight |
| **Repeatability** | High | High | High | Highest | Medium |
| **State Management** | None | Git | None | tfstate | None |
| **Infrastructure** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Tables** | ✅ | ✅ | ✅ | ❌ (SQL) | ✅ |
| **Cortex Services** | ✅ | ✅ | ✅ | ❌ (SQL) | ✅ |
| **SPCS** | ✅ | ✅ | ✅ | Partial | ❌ |
| **Seed Data** | Manual | Manual | ✅ | Manual | Manual |
| **Rollback** | Manual | Git revert | Manual | terraform destroy | Manual |

---

## Validation Scripts Summary

```
flux-utility-solutions/
├── scripts/
│   ├── validate/
│   │   ├── 01_validate_infrastructure.sql
│   │   ├── 02_validate_stages.sql
│   │   ├── 03_validate_grid_foundation.sql
│   │   ├── 04_validate_meters.sql
│   │   ├── 05_validate_customers.sql
│   │   ├── 06_validate_ami_pipeline.sql
│   │   ├── 07_validate_aggregations.sql
│   │   ├── 08_validate_cortex.sql
│   │   └── validate_sql_deployment.sh
│   └── 99_validate_deployment.sql
├── git_deploy/
│   └── validate_git_deployment.sql
├── cli/
│   ├── validate.py
│   └── validate_cli_deployment.sh
└── terraform/
    └── validate_terraform.sh
```

---

## Recommended Path by Use Case

| Use Case | Recommended Path | Reason |
|----------|------------------|--------|
| Quick demo | CLI Quickstart | 15-minute setup |
| Production deployment | Terraform + SQL | State management, repeatability |
| CI/CD pipeline | Git Integration | Auto-deploy on merge |
| Learning/exploration | Notebooks | Interactive, visual |
| Maximum control | SQL Scripts | Step-by-step, debug-friendly |

---

## Gap Analysis vs SI_DEMOS

| Component | SI_DEMOS | Repo Coverage | Gap |
|-----------|----------|---------------|-----|
| Core tables | 114 | 10 core + structure | Historical data not included |
| Views | 33 | 10+ | Some specialized views missing |
| Search services | 3 | 3 | ✅ Full coverage |
| Semantic views | 1 | 1 | ✅ Full coverage |
| Cortex agents | 3 | 1 | Customer & Transformer agents TBD |
| Row count | 7.1B | Seed data only | Data generation scripts provided |

---

*Report generated: January 2026*
*Repository: Snowflake-Labs/flux-utility-solutions*
