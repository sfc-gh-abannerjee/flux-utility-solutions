# Flux Utility Solutions

<p align="center">
  <img src="./images/flux_banner_6.png" alt="Flux Utility Solutions" width="100%"/>
</p>

[![Snowflake](https://img.shields.io/badge/Snowflake-29B5E8?logo=snowflake&logoColor=white)](https://www.snowflake.com)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

**Turn siloed utility data into an AI-ready grid intelligence platform — out of the box.** Unifies AMI meter readings, asset health metrics, customer records, and compliance documents on Snowflake so operations, engineering, and field teams can query grid data in plain English instead of waiting on reports.

> *"Data is the control plane for the future of energy."* — Fred Cohagan, Global Head of Energy, Snowflake
>
> Built to address the same challenges driving [Snowflake Energy Solutions](https://www.snowflake.com/en/solutions/industries/energy/): connecting IT, OT, and IoT data on one trusted platform to modernize grid operations and accelerate AI adoption across the energy sector.

---

## Why Flux Utility Solutions?

Utilities generate massive volumes of data — AMI readings, SCADA telemetry, asset inspections, customer interactions — but it sits in disconnected systems. Engineers wait days for cross-system reports. Compliance teams manually compile audit evidence. Operations staff can't get real-time answers without a data analyst in the loop.

This repository solves that by delivering a **production-ready data foundation and AI stack** on Snowflake:

| What You Get | Why It Matters |
|--------------|----------------|
| **Unified grid data model** | Substations, transformers, meters, and customers in one governed platform — no more IT/OT silos |
| **AI-powered grid intelligence** | Cortex Agent with 5 tools: text-to-SQL analytics, customer search, meter lookup, technical docs, and compliance docs — anyone can query the grid in natural language |
| **Five deployment paths** | CLI, SQL scripts, Notebooks, Git integration, or Terraform — fits your team's workflow |
| **Extensible platform** | Foundation for [Flux Data Forge](https://github.com/sfc-gh-abannerjee/flux-data-forge) (streaming data) and [Flux Ops Center](https://github.com/sfc-gh-abannerjee/flux-ops-center-spcs) (real-time grid visualization) |

---

## Quick Start

```bash
git clone https://github.com/sfc-gh-abannerjee/flux-utility-solutions.git
cd flux-utility-solutions
./cli/quickstart.sh -c <connection_name>
```

**What you get:** Database with schemas, core tables (Substations, Transformers, Meters, Customers), sample data, and warehouse configured.

---

## Snowflake Features

| Category | Features |
|----------|----------|
| **Cortex AI** | [Analyst](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst), [Search](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview), [Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents), [LLM Functions](https://docs.snowflake.com/en/user-guide/snowflake-cortex/llm-functions), [Semantic Views](https://docs.snowflake.com/en/user-guide/views-semantic) |
| **Data Engineering** | [Dynamic Tables](https://docs.snowflake.com/en/user-guide/dynamic-tables-about), [Streams](https://docs.snowflake.com/en/user-guide/streams-intro), [Tasks](https://docs.snowflake.com/en/user-guide/tasks-intro), [Snowpipe](https://docs.snowflake.com/en/user-guide/data-load-snowpipe-intro) |
| **Machine Learning** | [Snowpark ML](https://docs.snowflake.com/en/developer-guide/snowflake-ml/overview), [Model Registry](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/overview), [Feature Store](https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/overview) |
| **Applications** | [Streamlit](https://docs.snowflake.com/en/developer-guide/streamlit/about-streamlit), [SPCS](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/overview), [Notebooks](https://docs.snowflake.com/en/user-guide/ui-snowsight/notebooks) |

---

## Documentation

| Document | Description |
|----------|-------------|
| [DEPLOYMENT.md](./docs/DEPLOYMENT.md) | Step-by-step deployment guide |
| [ARCHITECTURE.md](./docs/ARCHITECTURE.md) | System design and diagrams |
| [AI_ARCHITECTURE.md](./docs/AI_ARCHITECTURE.md) | Cortex AI configuration |
| [DATA_MODEL.md](./docs/DATA_MODEL.md) | Schema documentation |
| [DEPENDENCIES.md](./docs/DEPENDENCIES.md) | Inter-repository dependencies |
| [TERRAFORM_GUIDE.md](./docs/TERRAFORM_GUIDE.md) | Infrastructure as Code guide |

---

## Architecture

```mermaid
flowchart TB
    subgraph APP["APPLICATION LAYER"]
        A1["Streamlit"] ~~~ A2["Cortex Agents"] ~~~ A3["Notebooks"] ~~~ A4["SPCS"]
    end
    
    subgraph ANALYTICS["ANALYTICS LAYER"]
        B1["Dynamic Tables"] ~~~ B2["Cortex Analyst"] ~~~ B3["Cortex Search"] ~~~ B4["Snowpark ML"]
    end
    
    subgraph DATA["DATA LAYER"]
        C1["AMI Readings"] ~~~ C2["Grid Topology"] ~~~ C3["Customers"] ~~~ C4["Assets"]
    end
    
    APP --> ANALYTICS --> DATA
    
    style APP fill:#1565c0,color:#fff,stroke:#0d47a1
    style ANALYTICS fill:#ef6c00,color:#fff,stroke:#e65100
    style DATA fill:#2e7d32,color:#fff,stroke:#1b5e20
```

**[Detailed Architecture →](./docs/ARCHITECTURE.md)**

---

## Features

Each capability maps to a real utility workflow — from grid planning and asset monitoring to customer operations and regulatory compliance.

<img width="2752" height="1301" alt="flux_utiility_components_readme" src="https://github.com/user-attachments/assets/ed510414-3856-4e1c-a7b6-bea77199faf0" />

<table>
<tr>
<td align="center"><img src="./images/flux_utility_SI_1.png" width="400"/><br/><b>Grid Intelligence Agent</b><br/>Natural language grid queries</td>
<td align="center"><img src="./images/flux_sis_h3_1.png" width="400"/><br/><b>H3 Grid Visualization</b><br/>Hexagonal topology maps</td>
</tr>
<tr>
<td align="center"><img src="./images/cortex_search_services_1.png" width="400"/><br/><b>Cortex Search Services</b><br/>Semantic customer search</td>
<td align="center"><img src="./images/transformer_failure_prediction_ml_notebook_1.png" width="400"/><br/><b>Predictive Maintenance</b><br/>ML-based risk scoring</td>
</tr>
</table>

| Use Case | What It Solves | Location |
|----------|----------------|----------|
| **Grid Visualization** | See real-time topology across substations and feeders — situational awareness for control rooms | `streamlit/geospatial/` |
| **AMI Analytics** | Analyze smart meter time-series at scale — detect anomalies, forecast load, reduce non-technical losses | `notebooks/demos/` |
| **Customer 360** | Unified customer view with semantic search across 686K profiles — faster service response | `scripts/09_cortex_search_services.sql` |
| **Predictive Maintenance** | ML-based transformer risk scoring — prevent failures before they cause outages | `scripts/11_ml_feature_tables.sql` |
| **Conversational Analytics** | Ask grid questions in plain English — democratize data access for operations and field teams | `agents/` |
| **Outage Management** | Real-time outage tracking and restoration prioritization | `streamlit/outage_dashboard.py` |

---

## Flux Platform Ecosystem

Together, these repos deliver a complete grid intelligence stack — from synthetic data generation through real-time operational visualization — mirroring the end-to-end workflows Snowflake Energy Solutions enables for utilities. Deploy this repo first, then add optional components:

```mermaid
flowchart LR
    subgraph Core["flux-utility-solutions"]
        C1[("Database<br/>Tables<br/>Cortex AI")]
    end
    
    subgraph Optional["Optional Components"]
        O1["flux-data-forge<br/>Synthetic Data"]
        O2["flux-ops-center<br/>Grid Visualization"]
    end
    
    Core --> O1
    Core --> O2
    
    style Core fill:#1565c0,color:#fff
    style Optional fill:#ef6c00,color:#fff
```

| Repository | Purpose | 
|------------|---------|
| **Flux Utility Solutions** (this repo) | Core data foundation — unified grid data model, Cortex AI agent, semantic views |
| [Flux Data Forge](https://github.com/sfc-gh-abannerjee/flux-data-forge) | Synthetic AMI data generation with streaming — simulate millions of meter readings |
| [Flux Ops Center](https://github.com/sfc-gh-abannerjee/flux-ops-center-spcs) | Real-time grid visualization and GNN cascade failure prediction — operational situational awareness |

<table>
<tr>
<td align="center"><img src="./images/crockett_substation_cascade_SI.png" width="400"/><br/><a href="https://github.com/sfc-gh-abannerjee/flux-ops-center-spcs"><b>Flux Ops Center</b></a><br/>Real-time grid visualization, GNN cascade analysis<br/><br/><a href="https://github.com/sfc-gh-abannerjee/flux-ops-center-spcs/blob/main/docs/DOCKER_IMAGES.md">Docker Images</a> · <a href="https://github.com/sfc-gh-abannerjee/flux-ops-center-spcs/blob/main/docs/deployment/">Deployment</a></td>
<td align="center"><img src="./images/flux_data_forge_generate_1.png" width="400"/><br/><a href="https://github.com/sfc-gh-abannerjee/flux-data-forge"><b>Flux Data Forge</b></a><br/>Synthetic data generation, streaming pipelines</td>
</tr>
</table>

> **Note:** Flux Data Forge and Flux Ops Center can also run standalone. See their READMEs.

---

## Deployment Options

> **One solution. Five ways to build.**

| Path | Best For | Guide |
|------|----------|-------|
| **CLI Quick Start** | Demos, POCs, fastest setup | `./cli/quickstart.sh -c <connection_name>` |
| **SQL Scripts** | Learning, auditing, step-by-step control | [scripts/](./scripts/) |
| **Notebooks** | Workshops, data science teams | [notebooks/](./notebooks/) |
| **Git Integration** | GitOps, CI/CD pipelines | [git_deploy/](./git_deploy/) |
| **Terraform** | Enterprise IaC, multi-environment | [terraform/](./terraform/) |

<img width="1834" height="228" alt="deployment_options" src="https://github.com/user-attachments/assets/2ef9c913-a38f-4604-8c42-1f9f067902dc" />

### Prerequisites

| Requirement | Notes |
|-------------|-------|
| Snowflake account | ACCOUNTADMIN role recommended |
| [Snow CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index) | Required for CLI deployment |
| Python 3.10+ | Optional: data generators |
| Terraform 1.5+ | Optional: IaC deployment |

---

## Sample Data

Bundled seed data for immediate exploration:

| Dataset | Records | Description |
|---------|---------|-------------|
| Substations | 269 | Grid infrastructure |
| Transformers | 100 | Asset health data |
| Meters | 100 | AMI metadata |
| Customers | 94 | Customer records |

```bash
# Generate more data
python generators/generate_all.py --size full
```

> **For large-scale AMI data (millions of rows), see** [Flux Data Forge](https://github.com/sfc-gh-abannerjee/flux-data-forge).

---

## Repository Structure

```
flux-utility-solutions/
├── cli/               # Quick start scripts
├── scripts/           # SQL deployment (01-30)
├── notebooks/         # Snowflake Notebooks
├── git_deploy/        # Git integration
├── terraform/         # Infrastructure as Code
├── streamlit/         # Streamlit apps
├── agents/            # Cortex Agent definitions
├── models/            # Semantic models
├── seed_data/         # Sample data (CSV, Parquet)
├── generators/        # Script-based generators
└── docs/              # Documentation
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Apache 2.0 - See [LICENSE](./LICENSE)

---

<p align="center">
  <strong>Built on Snowflake AI Data Cloud</strong><br/>
  <em>Part of the <a href="https://www.snowflake.com/en/solutions/industries/energy/">Snowflake Energy Solutions</a> ecosystem</em>
</p>
