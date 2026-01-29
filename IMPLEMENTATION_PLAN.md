# Flux Utility Solutions - Implementation Plan

**Created**: January 28, 2026  
**Author**: Cortex Code CLI (FDE Mode)  
**Status**: In Progress

---

## Executive Summary

This document captures the comprehensive plan for building Flux Utility Solutions - a multi-path deployment system for Snowflake utility industry applications. The goal is to enable anyone to recreate the entire Flux ecosystem from scratch using their preferred deployment method.

### Key Principles

1. **One Solution, Five Paths** - SQL scripts, notebooks, Git integration, CLI automation, and Terraform all deploy the same product
2. **Declarative + Idempotent** - Use `CREATE OR ALTER` and Jinja2 templating for repeatable deployments
3. **Zero Delta** - All paths produce identical results matching existing PRODUCTION and APPLICATIONS schemas
4. **FDE Best Practices** - Well-structured code with proper naming, RBAC, and documentation

---

## Source of Truth

### Existing Implementation (Reference)
| Component | Location | Description |
|-----------|----------|-------------|
| Database Rebuild | `/sql/rebuild/00-08*.sql` | Core infrastructure SQL |
| Semantic Model | `/flux_ops_center_spcs/backend/sql/CENTERPOINTENERGY_SEMANTIC_MODEL_UPDATED.yaml` | 30-table semantic model |
| SPCS Application | `/flux_ops_center_spcs/` | Full-stack React + FastAPI app |
| PostgreSQL Setup | `/sql/postgres_setup/01-05*.sql` | Managed Postgres configuration |
| Agent Configs | `/archive/config/agent_configs/` | Cortex Agent definitions |
| ML Notebooks | `/flux_ops_center_spcs/backend/ml/` | Transformer failure prediction |
| Geospatial Notebook | `/geospatial_demo/flux_geospatial_notebook_portable.ipynb` | Portable H3 demo |

### Target Snowflake Account
| Attribute | Value |
|-----------|-------|
| Account | YOUR_ACCOUNT |
| Connection | cpe_demo_CLI |
| Database | FLUX_DATABASE |
| Production Schema | FLUX_DATABASE.PRODUCTION |
| Applications Schema | FLUX_DATABASE.APPLICATIONS |
| PostgreSQL Instance | FLUX_OPERATIONS_POSTGRES |
| SPCS Service | FLUX_OPS_CENTER |

### Production Data Scale
| Table | Rows | Purpose |
|-------|------|---------|
| AMI_INTERVAL_READINGS | 7.1B | 15-min interval AMI data |
| TRANSFORMER_HOURLY_LOAD | 211M | Hourly transformer loading |
| TRANSFORMER_THERMAL_STRESS_MATERIALIZED | 198M | Thermal stress metrics |
| CUSTOMERS_MASTER_DATA | 686K | Customer profiles |
| METER_INFRASTRUCTURE | 597K | Meter assignments |
| TRANSFORMER_METADATA | 91.5K | Transformer fleet |
| SUBSTATIONS | 275 | Substation locations |

---

## Repository Structure

```
flux-utility-solutions/
├── README.md                           # Overview + quick start
├── ARCHITECTURE.md                     # 4-layer platform design
├── IMPLEMENTATION_PLAN.md              # This document
├── LICENSE                             # Apache 2.0
│
├── scripts/                            # PATH 1: SQL Scripts (Jinja2)
│   ├── config.yaml                     # Environment configuration
│   ├── 01_database_infrastructure.sql  # Database + schemas + roles
│   ├── 02_warehouses.sql               # Compute warehouses
│   ├── 03_substations_transformers.sql # Grid foundation tables
│   ├── 04_meters_infrastructure.sql    # Meter + pole tables
│   ├── 05_customers_master.sql         # Customer data tables
│   ├── 06_ami_readings_pipeline.sql    # AMI tables + Dynamic Tables
│   ├── 07_aggregation_tables.sql       # Hourly load, thermal stress
│   ├── 08_semantic_view.sql            # Cortex Analyst semantic view
│   ├── 09_cortex_search_services.sql   # Customer + meter search
│   ├── 10_cortex_agent.sql             # Grid Intelligence Agent
│   ├── 11_ml_feature_tables.sql        # ML training data
│   ├── 12_model_registry.sql           # Snowpark ML deployment
│   ├── 13_cascade_procedures.sql       # Graph analysis procedures
│   ├── 14_postgres_instance.sql        # Managed PostgreSQL
│   ├── 15_postgres_external_access.sql # EAI + secrets
│   ├── 16_postgres_sync_pipeline.sql   # CDC streams + tasks
│   ├── 17_spcs_infrastructure.sql      # Compute pools + service
│   ├── 18_geospatial_views.sql         # H3 spatial views
│   ├── 19_marketplace_integration.sql  # External data
│   ├── 98_grants_rbac.sql              # Role-based access control
│   └── 99_validation_queries.sql       # Verification queries
│
├── notebooks/                          # PATH 2: Snowflake Notebooks
│   ├── setup/
│   │   └── 01_full_deployment.ipynb    # Complete setup notebook
│   ├── demos/
│   │   ├── ami_analytics.ipynb         # 7.1B row queries
│   │   ├── customer_360_search.ipynb   # Cortex Search demo
│   │   ├── geospatial_h3.ipynb         # Portable H3 analysis
│   │   └── transformer_risk_ml.ipynb   # ML prediction
│   └── advanced/
│       └── cascade_simulation.ipynb    # Graph failure analysis
│
├── git_deploy/                         # PATH 3: Git Integration
│   ├── setup_git_repository.sql        # CREATE GIT REPOSITORY
│   └── deploy_from_git.sql             # EXECUTE IMMEDIATE FROM
│
├── cli/                                # PATH 4: Snowflake CLI
│   ├── deploy.sh                       # Full deployment
│   ├── quickstart.sh                   # 15-min seed data
│   ├── teardown.sh                     # Cleanup
│   ├── validate.sh                     # Verify deployment
│   ├── config/
│   │   ├── dev.env
│   │   ├── staging.env
│   │   └── prod.env
│   └── snow_connection.toml.template
│
├── terraform/                          # PATH 5: Infrastructure as Code
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   ├── modules/
│   │   ├── database/
│   │   ├── warehouse/
│   │   ├── tables/
│   │   ├── semantic_view/
│   │   ├── cortex_search/
│   │   ├── cortex_agent/
│   │   ├── postgres/
│   │   └── spcs/
│   └── environments/
│       ├── dev/
│       ├── staging/
│       └── prod/
│
├── models/                             # Semantic Models
│   ├── utility_semantic_model.yaml     # Full 30-table model
│   └── domain_views/
│       ├── ami_domain.yaml             # AMI-focused subset
│       └── grid_topology_domain.yaml   # Grid topology subset
│
├── agents/                             # Cortex Agent Definitions
│   ├── grid_intelligence_agent.yaml    # Main agent
│   └── tools/
│       └── cascade_analysis_proc.sql   # Custom tool
│
├── seed_data/                          # Pre-built Datasets
│   ├── small/                          # Quick start (<1GB)
│   │   └── README.md
│   └── full/                           # Production scale
│       └── README.md
│
├── generators/                         # Data Generation
│   ├── ami_generator.py
│   ├── customer_generator.py
│   └── requirements.txt
│
├── sync/                               # PostgreSQL Sync
│   ├── sync_to_postgres.py
│   └── requirements.txt
│
├── app/                                # SPCS Application
│   ├── README.md
│   ├── backend/
│   ├── frontend/
│   ├── docker/
│   └── config/
│       └── service_spec.yaml
│
├── docs/                               # Documentation
│   ├── DEMO_PLAYBOOK.md                # Talk track
│   ├── USE_CASE_MAP.md                 # Customer mapping
│   ├── PATH_COMPARISON.md              # Deployment guide
│   ├── TERRAFORM_GUIDE.md              # IaC deep-dive
│   └── KNOWN_GAPS.md                   # Data limitations
│
└── comparison/                         # Competitive Positioning
    ├── vs_palantir.md
    └── tco_calculator.xlsx
```

---

## Naming Conventions

### Database Objects (Standardized)

| Category | Pattern | Example |
|----------|---------|---------|
| Database | `FLUX_<ENV>` | `FLUX_PROD`, `FLUX_DEV` |
| Schema - Production | `PRODUCTION` | Data warehouse tables |
| Schema - Applications | `APPLICATIONS` | Views, services, agents |
| Schema - Raw | `RAW` | Staging data |
| Schema - ML | `ML` | Model registry, features |
| Warehouse | `FLUX_<ENV>_<SIZE>` | `FLUX_PROD_MEDIUM` |
| Compute Pool | `FLUX_<PURPOSE>_POOL` | `FLUX_INTERACTIVE_POOL` |
| PostgreSQL | `FLUX_<PURPOSE>_POSTGRES` | `FLUX_OPERATIONS_POSTGRES` |
| SPCS Service | `FLUX_<APP>_SERVICE` | `FLUX_OPS_CENTER_SERVICE` |
| Cortex Search | `<DOMAIN>_SEARCH_SERVICE` | `CUSTOMER_SEARCH_SERVICE` |
| Semantic View | `<DOMAIN>_SEMANTIC_VIEW` | `UTILITY_SEMANTIC_VIEW` |
| Cortex Agent | `<DOMAIN>_AGENT` | `GRID_INTELLIGENCE_AGENT` |

### Table Naming (Standardized)

| Domain | Pattern | Example |
|--------|---------|---------|
| Infrastructure | `<ASSET>_METADATA` | `TRANSFORMER_METADATA`, `METER_INFRASTRUCTURE` |
| Time-Series | `<SOURCE>_<GRAIN>_<TYPE>` | `AMI_INTERVAL_READINGS`, `AMI_MONTHLY_USAGE` |
| Aggregations | `<ASSET>_<GRAIN>_<METRIC>` | `TRANSFORMER_HOURLY_LOAD` |
| Customers | `CUSTOMERS_<ATTRIBUTE>` | `CUSTOMERS_MASTER_DATA` |
| External | `<SOURCE>_<DATA>` | `ERCOT_LMP_HOUSTON_ZONE`, `HOUSTON_WEATHER_HOURLY` |
| Geospatial | `<DOMAIN>_SPATIAL` | `POWER_LINES_SPATIAL`, `VEGETATION_RISK_ENHANCED` |

---

## Implementation Phases

### Phase 1: SQL Scripts (Priority: Highest)
Create 20 parameterized SQL files using Jinja2 templating.

**Jinja2 Variables:**
```yaml
# config.yaml
database: FLUX_PROD        # Target database
warehouse: FLUX_PROD_MEDIUM # Compute warehouse
role: FLUX_ADMIN_ROLE      # Admin role
user_role: FLUX_USER_ROLE  # End-user role
postgres_instance: FLUX_OPERATIONS_POSTGRES
compute_pool: FLUX_INTERACTIVE_POOL
```

**Pattern:**
```sql
-- 01_database_infrastructure.sql
-- Parameterized for {{ database }} deployment

CREATE DATABASE IF NOT EXISTS {{ database }};
CREATE OR ALTER WAREHOUSE {{ warehouse }}
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

CREATE SCHEMA IF NOT EXISTS {{ database }}.PRODUCTION;
CREATE SCHEMA IF NOT EXISTS {{ database }}.APPLICATIONS;
CREATE SCHEMA IF NOT EXISTS {{ database }}.RAW;
CREATE SCHEMA IF NOT EXISTS {{ database }}.ML;
```

### Phase 2: Semantic Model
Adapt existing 30-table model with:
- Sample values for categorical columns
- Synonyms for natural language
- Verified query responses (VQRs)
- Domain subsets for focused agents

### Phase 3: Cortex Agent
Follow 4-layer instruction pattern:
1. **Data Layer** - Semantic view references
2. **Orchestration** - Identity, scope, tool selection
3. **Response** - Tone, format, citations
4. **Tool Descriptions** - What each tool does

### Phase 4: CLI Automation
Create shell scripts using `snow` CLI:
```bash
# deploy.sh
snow git execute @flux_repo/branches/main/scripts/ \
    -D "database='FLUX_PROD'" \
    -D "warehouse='FLUX_PROD_MEDIUM'"
```

### Phase 5: Terraform Modules
Snowflake provider modules for enterprise IaC.

### Phase 6: Notebooks
Convert SQL scripts to interactive notebooks.

### Phase 7: Documentation
Write demo playbooks and guides.

---

## Testing Strategy

### Sandbox Environment
- **Schema**: `FLUX_DATABASE.FLUX_SANDBOX`
- **Purpose**: Test all deployment paths before production
- **Cleanup**: Drop schema after validation

### Validation Queries
```sql
-- 99_validation_queries.sql

-- 1. Verify table row counts
SELECT 'SUBSTATIONS' as table_name, COUNT(*) as row_count 
FROM {{ database }}.PRODUCTION.SUBSTATIONS
UNION ALL
SELECT 'TRANSFORMER_METADATA', COUNT(*) 
FROM {{ database }}.PRODUCTION.TRANSFORMER_METADATA
-- ... etc

-- 2. Verify referential integrity
SELECT 'Orphan Meters' as check_name, COUNT(*) as issues
FROM {{ database }}.PRODUCTION.METER_INFRASTRUCTURE m
LEFT JOIN {{ database }}.PRODUCTION.TRANSFORMER_METADATA t 
    ON m.TRANSFORMER_ID = t.TRANSFORMER_ID
WHERE t.TRANSFORMER_ID IS NULL

-- 3. Verify Cortex services
SHOW CORTEX SEARCH SERVICES IN SCHEMA {{ database }}.APPLICATIONS;
SHOW SEMANTIC VIEWS IN SCHEMA {{ database }}.APPLICATIONS;
```

---

## Git Workflow

### Repository
- **Remote**: `github.com/YOUR_ORG/flux-utility-solutions`
- **Main Branch**: `main` (protected)
- **Development**: Feature branches

### Commit Strategy
1. Initial commit: README.md + IMPLEMENTATION_PLAN.md
2. Commit per phase (SQL scripts, models, etc.)
3. Test in sandbox before merge
4. Tag releases (v1.0.0, v1.1.0, etc.)

---

## Deliverables Checklist

### SQL Scripts (scripts/)
- [ ] 01_database_infrastructure.sql
- [ ] 02_warehouses.sql
- [ ] 03_substations_transformers.sql
- [ ] 04_meters_infrastructure.sql
- [ ] 05_customers_master.sql
- [ ] 06_ami_readings_pipeline.sql
- [ ] 07_aggregation_tables.sql
- [ ] 08_semantic_view.sql
- [ ] 09_cortex_search_services.sql
- [ ] 10_cortex_agent.sql
- [ ] 11_ml_feature_tables.sql
- [ ] 12_model_registry.sql
- [ ] 13_cascade_procedures.sql
- [ ] 14_postgres_instance.sql
- [ ] 15_postgres_external_access.sql
- [ ] 16_postgres_sync_pipeline.sql
- [ ] 17_spcs_infrastructure.sql
- [ ] 18_geospatial_views.sql
- [ ] 19_marketplace_integration.sql
- [ ] 98_grants_rbac.sql
- [ ] 99_validation_queries.sql

### Configuration (models/, agents/)
- [ ] models/utility_semantic_model.yaml
- [ ] models/domain_views/ami_domain.yaml
- [ ] models/domain_views/grid_topology_domain.yaml
- [ ] agents/grid_intelligence_agent.yaml
- [ ] agents/tools/cascade_analysis_proc.sql

### CLI (cli/)
- [ ] cli/deploy.sh
- [ ] cli/quickstart.sh
- [ ] cli/teardown.sh
- [ ] cli/validate.sh
- [ ] cli/config/dev.env
- [ ] cli/config/staging.env
- [ ] cli/config/prod.env
- [ ] cli/snow_connection.toml.template

### Terraform (terraform/)
- [ ] terraform/main.tf
- [ ] terraform/variables.tf
- [ ] terraform/outputs.tf
- [ ] terraform/modules/database/main.tf
- [ ] terraform/modules/warehouse/main.tf
- [ ] terraform/modules/tables/main.tf
- [ ] terraform/modules/semantic_view/main.tf
- [ ] terraform/modules/cortex_search/main.tf
- [ ] terraform/modules/postgres/main.tf
- [ ] terraform/modules/spcs/main.tf

### Notebooks (notebooks/)
- [ ] notebooks/setup/01_full_deployment.ipynb
- [ ] notebooks/demos/ami_analytics.ipynb
- [ ] notebooks/demos/customer_360_search.ipynb
- [ ] notebooks/demos/geospatial_h3.ipynb
- [ ] notebooks/demos/transformer_risk_ml.ipynb
- [ ] notebooks/advanced/cascade_simulation.ipynb

### Documentation (docs/)
- [ ] docs/DEMO_PLAYBOOK.md
- [ ] docs/USE_CASE_MAP.md
- [ ] docs/PATH_COMPARISON.md
- [ ] docs/TERRAFORM_GUIDE.md
- [ ] docs/KNOWN_GAPS.md
- [ ] ARCHITECTURE.md

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| SQL syntax differences | Test each script in sandbox |
| Large data volumes (7.1B rows) | Use `SAMPLE` for testing |
| SPCS deployment complexity | Start with existing service spec |
| Terraform provider gaps | Document manual steps |
| Semantic model compatibility | Validate with Cortex Analyst |

---

## Success Criteria

1. **Zero Delta**: All 5 paths produce identical database objects
2. **Row Count Match**: Tables match existing PRODUCTION schema
3. **Service Operational**: SPCS service runs successfully
4. **Search Working**: Cortex Search services return results
5. **Agent Functional**: Cortex Agent answers queries correctly
6. **Postgres Synced**: CDC pipeline populates PostgreSQL

---

**Next Step**: Initialize Git repository and begin SQL script creation.
