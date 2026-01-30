# Flux Utility Solutions

## Reference Architecture for Utilities on Snowflake

A comprehensive solution accelerator demonstrating how utility companies can leverage Snowflake's AI Data Cloud for grid operations, customer analytics, and predictive maintenance.

> **One solution, five deployment paths.**
>
> Whether your team prefers SQL scripts, interactive notebooks, GitOps workflows, CLI automation, or Terraform - Flux has you covered.

---

## Overview

Flux Utility Solutions is a reference architecture for building utility industry applications on Snowflake's AI Data Cloud.

### Seed Data (Included)

Get started immediately with bundled sample data:

| Dataset | Records | Description |
|---------|---------|-------------|
| Substations | 269 | Houston metro transmission/distribution |
| Transformers | 100 | Asset health and specifications |
| Meters | 100 | AMI infrastructure |
| Customers | 94 | Customer master data |

### Scale It Up

Generate larger datasets for POCs and demos using the included tools:

| Tool | Location | Scale | Use Case |
|------|----------|-------|----------|
| **Flux Data Forge** | `spcs/flux_data_forge/` | Up to 350M+ rows | SPCS app with streaming demos |
| **Python Generators** | `generators/` | Up to 28M rows | Local generation scripts |
| **SQL Generator** | `scripts/51_generate_ami_sample.sql` | Configurable | In-Snowflake generation |

```bash
# Example: Generate 8.6M rows for SE demo
python generators/generate_all.py --size full

# Example: Deploy Flux Data Forge for streaming demos
cd spcs/flux_data_forge && ./build_and_push.sh
```

---

## Architecture

### 4-Layer Hybrid Platform

```
LAYER 4: APPLICATION     SPCS (React + DeckGL + FastAPI)
                         Full-stack grid operations center

LAYER 3: ANALYTICS       Snowflake Core
                         Dynamic Tables, Cortex AI, ML Models

LAYER 2: STREAMING       CDC Streams + Tasks
                         Event-driven synchronization

LAYER 1: TRANSACTIONAL   Snowflake Managed PostgreSQL
                         PostGIS geospatial, real-time cache
```

See [ARCHITECTURE.md](./docs/ARCHITECTURE.md) for detailed diagrams.

---

## Choose Your Deployment Path

| Path | Best For | Time | Getting Started |
|------|----------|------|-----------------|
| **1. CLI Quick Start** | Quick demos, POCs | ~1 min | `./cli/quickstart.sh` |
| **2. SQL Scripts** | Learning, auditing, manual control | 15-30 min | [scripts/README.md](./scripts/README.md) |
| **3. Notebooks** | POC workshops, data scientists | 20 min | [notebooks/README.md](./notebooks/README.md) |
| **4. Git Integration** | Modern DevOps, GitOps workflows | 15 min | [git_deploy/README.md](./git_deploy/README.md) |
| **5. Terraform** | Enterprise IaC, multi-environment | 10 min | [terraform/README.md](./terraform/README.md) |

---

## Quick Start (Fastest Path)

Get a working environment in under 2 minutes:

```bash
# 1. Clone the repository
git clone https://github.com/Snowflake-Labs/flux-utility-solutions.git
cd flux-utility-solutions

# 2. Ensure Snow CLI is installed and configured
snow connection list   # Should show at least one connection

# 3. Run quick start (creates FLUX_QUICKSTART database)
./cli/quickstart.sh

# Or specify your own database/connection:
./cli/quickstart.sh --database MY_DB --connection my_connection
```

**What gets deployed:**
- Database with PRODUCTION, APPLICATIONS, SECRETS schemas
- Warehouse (XSMALL, auto-suspend 60s)
- Core tables: Substations, Transformers, Meters, Customers
- Time-series tables for AMI readings
- Sample seed data loaded

---

## Important: Variable Templating

Different deployment paths use **different variable syntax**:

| Path | Syntax | Example |
|------|--------|---------|
| **Scripts** (Snow CLI) | `<% variable %>` | `CREATE DATABASE <% database %>` |
| **Notebooks** | `$variable` | `SET db = 'X'; USE DATABASE IDENTIFIER($db)` |
| **Git Integration** | `$variable` (USING clause) | `EXECUTE IMMEDIATE FROM ... USING (db => 'X')` |
| **Terraform** | `var.variable` | `var.database_name` |

See each path's README for detailed syntax examples.

---

## Manual Deployment (SQL Scripts)

For more control, deploy step-by-step with Snow CLI:

```bash
cd scripts

# Set your connection and target
export CONN="your_connection_name"
export DB="FLUX_DEV"
export WH="FLUX_DEV_WH"

# 1. Infrastructure
snow sql -c $CONN -f 01_database_infrastructure.sql \
    -D "database=$DB" -D "admin_role=ACCOUNTADMIN" -D "user_role=PUBLIC"

snow sql -c $CONN -f 02_warehouses.sql \
    -D "database=$DB" -D "warehouse=$WH" -D "warehouse_size=SMALL"

# 2. Core tables
snow sql -c $CONN -f 03_substations_transformers.sql -D "database=$DB" -D "warehouse=$WH"
snow sql -c $CONN -f 04_meters_infrastructure.sql -D "database=$DB" -D "warehouse=$WH"
snow sql -c $CONN -f 05_customers_master.sql -D "database=$DB" -D "warehouse=$WH"

# 3. Load seed data
snow sql -c $CONN -f 50_load_seed_data.sql -D "database=$DB" -D "warehouse=$WH"
```

---

## Repository Structure

```
flux-utility-solutions/
├── scripts/           # SQL deployment scripts (01-99)
├── notebooks/         # Snowflake Notebooks (.ipynb)
├── git_deploy/        # Git integration deployment
├── cli/               # Shell automation scripts
├── terraform/         # Infrastructure as Code
├── models/            # Cortex Analyst semantic models
├── agents/            # Cortex Agent definitions
├── streamlit/         # Streamlit in Snowflake apps
├── seed_data/         # Sample data (CSV, Parquet)
├── generators/        # Synthetic data generation
├── spcs/              # Container services (SPCS)
├── sync/              # External sync scripts
└── docs/              # Documentation
```

---

## Snowflake Capabilities Demonstrated

### Cortex AI
- **Cortex Analyst** - 30+ table semantic model with natural language SQL
- **Cortex Agent** - Multi-tool agent with cascade analysis procedures
- **Cortex Search** - 5 search services (1.3M+ indexed documents)

### Data Engineering
- **Dynamic Tables** - Declarative Bronze→Silver→Gold pipeline
- **CDC Streams** - Real-time change data capture
- **Snowpipe** - Automated data ingestion

### Machine Learning
- **Snowpark ML** - XGBoost transformer failure prediction
- **Model Registry** - Versioned models with governance
- **SHAP Explainability** - Feature importance analysis

### Infrastructure
- **SPCS** - Full-stack containerized application
- **Managed PostgreSQL** - PostGIS-enabled operational cache
- **External Access** - Secure outbound network integrations

### Geospatial
- **H3 Functions** - 43 native hexagonal indexing functions
- **PostGIS** - Advanced spatial queries in PostgreSQL
- **DeckGL** - High-performance map visualization

---

## Use Cases Covered

| # | Use Case | Solution | Module |
|---|----------|----------|--------|
| 1 | AMI Data Management | Dynamic Tables + 7.1B rows | `scripts/04_*` |
| 2 | Estimated Restoration | PostgreSQL <20ms queries | `scripts/13-15_*` |
| 3 | Digital Twin | DeckGL + 66K feeder visualization | `app/` |
| 4 | Customer 360 | Cortex Search + embeddings | `scripts/07_*` |
| 5 | Conversational AI | Cortex Agent + Semantic Views | `scripts/12_*` |
| 6 | Document Intelligence | PDF RAG (20K chunks) | `scripts/07_*` |
| 7 | Predictive Maintenance | ML with SHAP explainability | `scripts/08-09_*` |
| 8 | Cascade Analysis | Graph procedures + centrality | `scripts/10-11_*` |

---

## Prerequisites

- Snowflake account with ACCOUNTADMIN role
- Python 3.10+ (for generators and sync scripts)
- Docker (for SPCS deployment)
- Terraform 1.5+ (for IaC path)

---

## Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](./docs/ARCHITECTURE.md) | System architecture diagrams |
| [DATA_MODEL.md](./docs/DATA_MODEL.md) | Database schema and relationships |
| [USE_CASE_MAP.md](./docs/USE_CASE_MAP.md) | Customer need → module mapping |
| [PATH_COMPARISON.md](./docs/PATH_COMPARISON.md) | When to use each deployment path |
| [TERRAFORM_GUIDE.md](./docs/TERRAFORM_GUIDE.md) | Infrastructure as Code deep-dive |
| [SEED_DATA_GUIDE.md](./docs/SEED_DATA_GUIDE.md) | Loading seed data into Snowflake |
| [CORTEX_GUIDE.md](./docs/CORTEX_GUIDE.md) | Cortex AI features and configuration |
| [DEPLOYMENT.md](./docs/DEPLOYMENT.md) | Detailed deployment instructions |

---

## License

Apache 2.0 - See [LICENSE](./LICENSE)

---

## Contributing

Contributions welcome! Please see our contributing guidelines and ensure all changes pass validation tests.

---

**Built with Cortex Code CLI** | **Snowflake AI Data Cloud**
