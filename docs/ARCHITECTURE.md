# Flux Utility Solutions - Architecture

A comprehensive reference architecture for utility companies building grid operations and analytics solutions on Snowflake's AI Data Cloud.

## Overview

Flux Utility Solutions demonstrates a **modern data platform architecture** that combines real-time operations, large-scale analytics, and AI capabilities in a unified solution.

```mermaid
flowchart TB
    subgraph APP["APPLICATION LAYER"]
        A1["Streamlit Apps"] ~~~ A2["Cortex Agents"] ~~~ A3["Notebooks"] ~~~ A4["SPCS Services"]
    end
    
    subgraph ANALYTICS["ANALYTICS LAYER"]
        B1["Dynamic Tables"] ~~~ B2["Cortex Analyst"] ~~~ B3["Cortex Search"] ~~~ B4["Snowpark ML"]
    end
    
    subgraph DATA["DATA LAYER"]
        C1["AMI Readings"] ~~~ C2["Grid Topology"] ~~~ C3["Customer Data"] ~~~ C4["Asset Metadata"]
    end
    
    APP --> ANALYTICS --> DATA
    
    style APP fill:#1565c0,color:#fff,stroke:#0d47a1
    style ANALYTICS fill:#ef6c00,color:#fff,stroke:#e65100
    style DATA fill:#2e7d32,color:#fff,stroke:#1b5e20
```

---

## Core Components

### Data Layer

The foundation layer stores and manages all utility data in Snowflake:

| Schema | Purpose | Key Objects |
|--------|---------|-------------|
| **PRODUCTION** | Core operational data | Substations, Transformers, Meters, Customers |
| **APPLICATIONS** | AI services and apps | Semantic Views, Search Services, Streamlit Apps |
| **SECRETS** | Credentials and configs | API keys, connection strings |

**Data Flow:**

```mermaid
flowchart LR
    SUB["Substations"] --> CIR["Circuits"] --> TRF["Transformers"] --> MTR["Meters"] --> CUS["Customers"]
    
    style SUB fill:#1565c0,color:#fff
    style CIR fill:#0277bd,color:#fff
    style TRF fill:#00838f,color:#fff
    style MTR fill:#00695c,color:#fff
    style CUS fill:#2e7d32,color:#fff
```

### Analytics Layer

Leverages Snowflake's native capabilities for advanced analytics:

| Capability | Use Case | Implementation |
|------------|----------|----------------|
| **Dynamic Tables** | Bronze → Silver → Gold pipelines | Declarative transformations |
| **Cortex Analyst** | Natural language SQL | Semantic models with relationships |
| **Cortex Search** | RAG and document search | Customer, meter, and document indices |
| **Snowpark ML** | Predictive maintenance | XGBoost transformer risk models |

### Application Layer

Multiple interfaces for different user personas:

| Application | Technology | Purpose |
|-------------|------------|---------|
| **Geospatial H3 App** | Streamlit | H3 hexagonal grid visualization |
| **Grid Map App** | Streamlit | Real-time topology monitoring |
| **Load Analytics** | Streamlit | Transformer capacity analysis |
| **Outage Dashboard** | Streamlit | Outage tracking and restoration |
| **Grid Intelligence Agent** | Cortex Agent | Conversational analytics assistant |

---

## AI Capabilities Overview

```mermaid
flowchart TB
    subgraph Analyst["CORTEX ANALYST"]
        A1["Natural Language"] ~~~ A2["Semantic Model"] ~~~ A3["SQL Generation"]
    end
    
    subgraph Search["CORTEX SEARCH"]
        S1["Customers"] ~~~ S2["Meters"] ~~~ S3["Documents"]
    end
    
    subgraph Agent["CORTEX AGENT"]
        G1["Multi-Tool"] ~~~ G2["Orchestration"] ~~~ G3["Cascading"]
    end
    
    Analyst --> Search --> Agent
    
    style Analyst fill:#1565c0,color:#fff
    style Search fill:#ef6c00,color:#fff
    style Agent fill:#7b1fa2,color:#fff
```

See [AI_ARCHITECTURE.md](./AI_ARCHITECTURE.md) for detailed configuration.

---

## Detailed Documentation

| Document | Description |
|----------|-------------|
| [AI_ARCHITECTURE.md](./AI_ARCHITECTURE.md) | Cortex Analyst, Search, and Agent configuration |
| [DEPLOYMENT_ARCHITECTURE.md](./DEPLOYMENT_ARCHITECTURE.md) | Five deployment paths and phases |
| [SECURITY.md](./SECURITY.md) | RBAC roles and permission matrix |
| [SCALABILITY.md](./SCALABILITY.md) | Data volumes and warehouse sizing |
| [DATA_MODEL.md](./DATA_MODEL.md) | Detailed schema documentation |
| [CORTEX_GUIDE.md](./CORTEX_GUIDE.md) | AI features configuration |
| [TERRAFORM_GUIDE.md](./TERRAFORM_GUIDE.md) | Infrastructure as Code guide |
| [DEPLOYMENT.md](./DEPLOYMENT.md) | Step-by-step deployment |

---

## Quick Reference

### Deployment Paths

```mermaid
flowchart TB
    REPO["flux-utility-solutions/"]
    
    subgraph Paths["DEPLOYMENT OPTIONS"]
        SQL["SQL Scripts"] ~~~ NB["Notebooks"] ~~~ GIT["Git Integration"] ~~~ CLI["CLI"] ~~~ TF["Terraform"]
    end
    
    REPO --> Paths
    
    style REPO fill:#37474f,color:#fff
    style Paths fill:#1565c0,color:#fff
```

### Security Roles

```mermaid
flowchart TB
    AA["ACCOUNTADMIN"]
    
    subgraph Admin["ADMINISTRATION"]
        FA["FLUX_ADMIN"]
    end
    
    subgraph Ops["OPERATIONAL ROLES"]
        FU["FLUX_USER"] ~~~ FE["FLUX_ETL"] ~~~ FS["FLUX_SERVICE"]
    end
    
    AA --> Admin --> Ops
    
    style AA fill:#b71c1c,color:#fff
    style Admin fill:#1565c0,color:#fff
    style Ops fill:#ef6c00,color:#fff
```

---

## Getting Started

1. **Choose your deployment path** based on team preferences
2. **Clone the repository** and review documentation
3. **Configure connection** using Snow CLI or Terraform
4. **Deploy infrastructure** following the chosen path
5. **Load seed data** for immediate exploration
6. **Explore applications** - Streamlit apps and notebooks

See [README.md](../README.md) for quick start instructions.
