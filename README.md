# Flux Utility Solutions

## Production-Grade Reference Architecture for Utilities on Snowflake

> **One solution, five deployment paths.**
>
> Whether your team prefers SQL scripts, interactive notebooks, GitOps workflows, CLI automation, or enterprise-grade Terraform - Flux has you covered.

---

## Overview

Flux Utility Solutions is the definitive reference architecture for building utility industry applications on Snowflake's AI Data Cloud. Unlike sample demos, this solution was architected to handle **production-scale** workloads:

| Metric | Scale |
|--------|-------|
| AMI Readings | 7.1 billion rows |
| Transformers | 91,554 assets |
| Customers | 686,359 records |
| Meters | 596,906 indexed |
| Feeder Lines | 66,000 visualized |
| Operational Query | <20ms (PostgreSQL) |
| Analytics Query | <5s (Snowflake) |

---

## Architecture

### 4-Layer Hybrid Platform

```
LAYER 4: APPLICATION     SPCS (React + DeckGL + FastAPI)
         ~3s load        Full-stack grid operations center

LAYER 3: ANALYTICS       Snowflake Core (7.1B AMI rows)
         <5s queries     Dynamic Tables, Cortex AI, ML Models

LAYER 2: STREAMING       CDC Streams + Tasks
         <1 min lag      Event-driven synchronization

LAYER 1: TRANSACTIONAL   Snowflake Managed PostgreSQL
         <20ms queries   PostGIS geospatial, real-time cache
```

See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed diagrams.

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
├── seed_data/         # Pre-built parquet datasets
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
| [ARCHITECTURE.md](./ARCHITECTURE.md) | System architecture diagrams |
| [docs/DEMO_PLAYBOOK.md](./docs/DEMO_PLAYBOOK.md) | What to show, what to say |
| [docs/USE_CASE_MAP.md](./docs/USE_CASE_MAP.md) | Customer need → module mapping |
| [docs/PATH_COMPARISON.md](./docs/PATH_COMPARISON.md) | When to use each deployment path |
| [docs/TERRAFORM_GUIDE.md](./docs/TERRAFORM_GUIDE.md) | Infrastructure as Code deep-dive |
| [docs/KNOWN_GAPS.md](./docs/KNOWN_GAPS.md) | Data limitations and workarounds |

---

## License

Apache 2.0 - See [LICENSE](./LICENSE)

---

## Contributing

Contributions welcome! Please see our contributing guidelines and ensure all changes pass validation tests.

---

**Built with Cortex Code CLI** | **Snowflake AI Data Cloud**
