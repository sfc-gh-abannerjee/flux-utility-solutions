# Deployment Path Comparison

> **One Solution, Five Deployment Paths** - Same infrastructure, your choice of deployment method.

This document compares all five deployment paths available for Flux Utility Solutions. Each path deploys identical infrastructure with zero delta between them.

## Overview Matrix

| Capability | SQL Scripts | Notebooks | Git Integration | CLI Shell | Terraform |
|------------|-------------|-----------|-----------------|-----------|-----------|
| **Full Deployment** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Incremental Updates** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **State Management** | Manual | Manual | Git-based | Manual | State file |
| **Rollback Support** | Manual | Manual | Git revert | Manual | `terraform destroy` |
| **CI/CD Ready** | ⚠️ Limited | ⚠️ Limited | ✅ Native | ✅ Native | ✅ Native |
| **Team Collaboration** | ⚠️ Manual | ✅ Snowsight | ✅ Git PRs | ✅ Git PRs | ✅ Git PRs |
| **Audit Trail** | Query history | Notebook history | Git commits | Logs | State + Git |
| **Learning Curve** | Low | Low | Medium | Medium | High |
| **Best For** | Quick demos | Education | DevOps teams | Automation | Enterprise |

---

## Path 1: SQL Scripts

**Location**: `scripts/`

### When to Use
- Quick demonstrations and POCs
- Learning Snowflake features
- Manual one-time deployments
- Debugging and troubleshooting

### Deployment Order
```
01_database_setup.sql          # Foundation
02_roles_and_grants.sql        # Security
03_warehouses.sql              # Compute
04_tables_dimensions.sql       # Dimension tables
05_tables_facts.sql            # Fact tables
06_tables_streaming.sql        # Streaming targets
07_external_data.sql           # External sources
08_dynamic_tables.sql          # Aggregations
09_streams_tasks.sql           # CDC pipeline
10_cortex_search.sql           # Search services
11_semantic_view.sql           # Cortex Analyst
12_cortex_agents.sql           # AI agents
13_spcs_infrastructure.sql     # Container services
...
23_postgres_external_access.sql # PostgreSQL EAI
24_postgres_sync_pipeline.sql  # CDC to PostgreSQL
```

### Execution
```sql
-- Execute in Snowsight or SnowSQL
!source scripts/01_database_setup.sql
!source scripts/02_roles_and_grants.sql
-- ... continue in order
```

### Jinja2 Variables
All scripts use Jinja2 templating:
```sql
USE DATABASE {{ database }};        -- e.g., FLUX_PROD
USE WAREHOUSE {{ warehouse }};      -- e.g., FLUX_WH
USE ROLE {{ admin_role }};          -- e.g., FLUX_ADMIN
```

### Pros & Cons
| Pros | Cons |
|------|------|
| Simple, readable | No state management |
| Easy to customize | Manual execution order |
| Great for learning | No automatic rollback |
| Copy-paste friendly | Hard to track changes |

---

## Path 2: Notebooks

**Location**: `notebooks/`

### When to Use
- Training and education
- Interactive exploration
- Demos with live commentary
- Step-by-step tutorials

### Structure
```
notebooks/
├── setup/
│   └── 01_full_deployment.ipynb     # Complete deployment
├── demos/
│   ├── ami_analytics.ipynb          # 7.1B row queries
│   ├── customer_360_search.ipynb    # Cortex Search
│   ├── geospatial_h3.ipynb          # H3 spatial analysis
│   ├── transformer_risk_ml.ipynb    # ML model training
│   └── cascade_simulation.ipynb     # GNN failure prediction
└── advanced/
    └── cascade_simulation.ipynb     # Advanced ML
```

### Execution
1. Upload to Snowsight: **Projects** → **Notebooks** → **Import**
2. Set Python environment and warehouse
3. Run cells sequentially

### Pros & Cons
| Pros | Cons |
|------|------|
| Visual, interactive | Requires Snowsight access |
| Great for demos | Not scriptable |
| Built-in documentation | Limited version control |
| Easy sharing | Manual execution |

---

## Path 3: Git Integration

**Location**: Root repository

### When to Use
- Team collaboration
- Version-controlled deployments
- Pull request workflows
- Audit compliance requirements

### Setup
```sql
-- Create Git repository integration
CREATE OR REPLACE GIT REPOSITORY flux_utility_solutions
  API_INTEGRATION = github_api_integration
  GIT_CREDENTIALS = github_credentials
  ORIGIN = 'https://github.com/Snowflake-Labs/flux-utility-solutions.git';

-- Fetch latest
ALTER GIT REPOSITORY flux_utility_solutions FETCH;

-- Execute from repository
EXECUTE IMMEDIATE FROM @flux_utility_solutions/branches/main/scripts/01_database_setup.sql
  USING (database => 'FLUX_PROD', warehouse => 'FLUX_WH', admin_role => 'FLUX_ADMIN');
```

### CI/CD Integration
```yaml
# .github/workflows/deploy.yml
name: Deploy to Snowflake
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy SQL
        run: |
          snowsql -c ${{ secrets.SNOWFLAKE_CONNECTION }} \
            -f scripts/01_database_setup.sql \
            -D database=FLUX_PROD
```

### Pros & Cons
| Pros | Cons |
|------|------|
| Full version control | Requires Git integration setup |
| PR review workflow | More complex initial setup |
| Automatic deployments | Requires CI/CD knowledge |
| Complete audit trail | GitHub API integration needed |

---

## Path 4: CLI Shell Scripts

**Location**: `cli/`

### When to Use
- Automated deployments
- Scripted environment setup
- CI/CD pipelines
- Scheduled maintenance

### Structure
```
cli/
├── deploy.sh                # Full deployment
├── validate.sh              # Validation checks
├── teardown.sh              # Clean removal
└── config/
    ├── dev.env              # Development config
    ├── staging.env          # Staging config
    └── prod.env             # Production config
```

### Usage
```bash
# Set environment
export FLUX_ENV=prod
source cli/config/prod.env

# Deploy everything
./cli/deploy.sh

# Deploy specific component
./cli/deploy.sh --component cortex

# Validate deployment
./cli/validate.sh

# Teardown (with confirmation)
./cli/teardown.sh --confirm
```

### Environment Variables
```bash
# cli/config/prod.env
export SNOWFLAKE_ACCOUNT="your_account"
export SNOWFLAKE_DATABASE="FLUX_PROD"
export SNOWFLAKE_WAREHOUSE="FLUX_WH"
export SNOWFLAKE_ROLE="FLUX_ADMIN"
export FLUX_ADMIN_ROLE="FLUX_ADMIN"
export FLUX_USER_ROLE="FLUX_USER"
```

### Pros & Cons
| Pros | Cons |
|------|------|
| Fully automated | Requires shell access |
| Environment configs | SnowSQL/Snow CLI needed |
| CI/CD native | Platform-specific (bash) |
| Idempotent operations | Error handling complexity |

---

## Path 5: Terraform

**Location**: `terraform/`

### When to Use
- Enterprise infrastructure as code
- Multi-environment management
- State-tracked deployments
- Complex dependency management

### Structure
```
terraform/
├── main.tf                  # Root configuration
├── variables.tf             # Input variables
├── outputs.tf               # Output values
├── environments/
│   ├── dev.tfvars           # Development
│   ├── staging.tfvars       # Staging
│   └── prod.tfvars          # Production
└── modules/
    ├── database/            # Database & schemas
    ├── warehouse/           # Compute resources
    ├── tables/              # Data tables
    ├── semantic_view/       # Cortex Analyst
    ├── cortex_search/       # Search services
    ├── cortex_agent/        # AI agents
    ├── postgres/            # PostgreSQL managed service
    └── spcs/                # Container services
```

### Usage
```bash
# Initialize
cd terraform
terraform init

# Plan (dry run)
terraform plan -var-file="environments/prod.tfvars"

# Apply
terraform apply -var-file="environments/prod.tfvars"

# Destroy (careful!)
terraform destroy -var-file="environments/prod.tfvars"
```

### State Management
```hcl
# Remote state (recommended for teams)
terraform {
  backend "s3" {
    bucket = "flux-terraform-state"
    key    = "prod/terraform.tfstate"
    region = "us-west-2"
  }
}
```

### Pros & Cons
| Pros | Cons |
|------|------|
| State management | Steeper learning curve |
| Dependency graph | Provider limitations |
| Plan before apply | Some features need unsafe_execute |
| Multi-cloud support | State file management |

---

## Decision Guide

### Choose SQL Scripts if:
- You're doing a quick demo
- Learning Snowflake features
- One-time deployment
- Need maximum flexibility

### Choose Notebooks if:
- Training or education setting
- Want visual, interactive deployment
- Demo with live commentary
- Step-by-step tutorials

### Choose Git Integration if:
- Team collaboration required
- Need PR review workflow
- Compliance/audit requirements
- Want CI/CD automation

### Choose CLI Shell if:
- Automating deployments
- Building CI/CD pipelines
- Need environment configs
- Prefer command-line

### Choose Terraform if:
- Enterprise IaC standards
- Multi-environment management
- Need state tracking
- Complex dependencies

---

## Migration Between Paths

### SQL → Terraform
1. Export current state: `SHOW OBJECTS`
2. Import into Terraform state
3. Run `terraform plan` to verify

### Terraform → SQL
1. Use `terraform show` to see resources
2. Generate SQL from state
3. Execute SQL scripts

### Any Path → Git Integration
1. Commit all scripts/configs to Git
2. Set up repository integration
3. Deploy from repository

---

## Validation Checklist

After deployment via ANY path, verify:

```sql
-- Database exists
SHOW DATABASES LIKE 'FLUX%';

-- Tables created
SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_SCHEMA = 'PRODUCTION';

-- Cortex services active
SHOW CORTEX SEARCH SERVICES;

-- SPCS running
SHOW SERVICES;

-- Semantic views ready
SHOW SEMANTIC VIEWS;

-- Agents available
SHOW CORTEX AGENTS;
```

---

## Summary

All five paths deploy **identical infrastructure**. Choose based on:

1. **Team expertise** - SQL for beginners, Terraform for DevOps
2. **Collaboration needs** - Git for teams, Notebooks for training
3. **Automation requirements** - CLI/Terraform for CI/CD
4. **Compliance** - Git/Terraform for audit trails

The goal is **flexibility without compromise** - same result, your preferred workflow.
