# Flux Utility Solutions

## Reference Architecture for Utilities on Snowflake

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

| Path | Best For | Time | Command |
|------|----------|------|---------|
| **1. SQL Scripts** | Learning, auditing, manual control | 45 min | `snow sql -f scripts/01_database_infrastructure.sql` |
| **2. Notebooks** | POC workshops, data scientists | 30 min | Import to Snowsight |
| **3. Git Integration** | Modern DevOps, GitOps workflows | 20 min | `CREATE GIT REPOSITORY` |
| **4. CLI** | Quick demos, automation | 15 min | `./cli/deploy.sh` |
| **5. Terraform** | Enterprise IaC, multi-environment | 20 min | `terraform apply` |

### Quick Start (Seed Data Path)

```bash
# Clone the repository
git clone https://github.com/Snowflake-Labs/flux-utility-solutions.git
cd flux-utility-solutions

# Configure Snowflake connection
cp cli/snow_connection.toml.template ~/.snowflake/connections.toml
# Edit with your credentials

# Deploy with seed data (15 minutes)
./cli/quickstart.sh
```

### Full Deployment

```bash
# Deploy everything including SPCS application
./cli/deploy.sh
```

---

## Repository Structure

```
flux-utility-solutions/
├── scripts/           # Path 1: Numbered SQL files (01-99)
├── notebooks/         # Path 2: Snowflake Notebooks (.ipynb)
├── git_deploy/        # Path 3: Git integration setup
├── cli/               # Path 4: Shell deployment scripts
├── terraform/         # Path 5: Infrastructure as Code
├── models/            # Cortex Analyst semantic models
├── agents/            # Cortex Agent definitions
├── seed_data/         # Bundled CSV seed data + PostgreSQL scripts
│   ├── csv/           # Sample data (substations, transformers, meters, customers)
│   └── postgresql/    # PostgreSQL schema and loading scripts
├── generators/        # Synthetic data generation (optional)
├── sync/              # PostgreSQL sync scripts
├── app/               # SPCS application source
├── docs/              # Demo playbooks and guides
└── comparison/        # vs. other solutions
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
| [docs/DEMO_PLAYBOOK.md](./docs/DEMO_PLAYBOOK.md) | What to show, what to say |
| [docs/USE_CASE_MAP.md](./docs/USE_CASE_MAP.md) | Customer need → module mapping |
| [docs/PATH_COMPARISON.md](./docs/PATH_COMPARISON.md) | When to use each deployment path |
| [docs/TERRAFORM_GUIDE.md](./docs/TERRAFORM_GUIDE.md) | Infrastructure as Code deep-dive |
| [docs/SEED_DATA_GUIDE.md](./docs/SEED_DATA_GUIDE.md) | Loading seed data into Snowflake/PostgreSQL |
| [docs/KNOWN_GAPS.md](./docs/KNOWN_GAPS.md) | Data limitations and workarounds |

---

## License

Apache 2.0 - See [LICENSE](./LICENSE)

---

## Contributing

Contributions welcome! Please see our contributing guidelines and ensure all changes pass validation tests.

---

**Built with Cortex Code CLI** | **Snowflake AI Data Cloud**
