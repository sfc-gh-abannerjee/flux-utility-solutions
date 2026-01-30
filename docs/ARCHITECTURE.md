# Flux Utility Solutions - Architecture

A comprehensive reference architecture for utility companies building grid operations and analytics solutions on Snowflake's AI Data Cloud.

## Overview

Flux Utility Solutions demonstrates a **modern data platform architecture** that combines real-time operations, large-scale analytics, and AI capabilities in a unified solution.

```mermaid
flowchart TB
    subgraph APP["APPLICATION LAYER"]
        direction LR
        A1["Streamlit Apps"]
        A2["Cortex Agents"]
        A3["Notebooks"]
        A4["SPCS Services"]
    end
    
    subgraph ANALYTICS["ANALYTICS LAYER"]
        direction LR
        B1["Dynamic Tables"]
        B2["Cortex Analyst"]
        B3["Cortex Search"]
        B4["Snowpark ML"]
    end
    
    subgraph DATA["DATA LAYER · Snowflake Data Cloud"]
        direction LR
        C1["AMI Readings"]
        C2["Grid Topology"]
        C3["Customer Data"]
        C4["Asset Metadata"]
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

**Key Data Domains:**

```mermaid
flowchart TD
    SUB["SUBSTATIONS<br/>Grid infrastructure backbone"]
    CIR["CIRCUITS<br/>Distribution feeders"]
    TRF["TRANSFORMERS<br/>Asset fleet with load data"]
    MTR["METERS<br/>AMI smart meter network"]
    CUS["CUSTOMERS<br/>Customer master data"]
    
    SUB --> CIR --> TRF --> MTR --> CUS
    
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
| **Notebooks** | Snowflake Notebooks | Interactive data exploration |

---

## AI Architecture

### Cortex Analyst (Natural Language SQL)

Enables business users to query data using natural language:

```mermaid
flowchart TD
    subgraph Question["USER QUESTION"]
        Q["What's the total load on substation 5?"]
    end
    
    subgraph Semantic["SEMANTIC VIEW"]
        T["Tables<br/>(30+)"]
        R["Relationships<br/>& Joins"]
        M["Metrics<br/>& Measures"]
    end
    
    subgraph SQL["SQL GENERATION"]
        G["Automatic query construction<br/>with proper joins"]
    end
    
    subgraph Results["QUERY RESULTS"]
        RES["Formatted response to user"]
    end
    
    Question --> Semantic --> SQL --> Results
    
    style Question fill:#1565c0,color:#fff
    style Semantic fill:#ef6c00,color:#fff
    style SQL fill:#7b1fa2,color:#fff
    style Results fill:#2e7d32,color:#fff
```

### Cortex Search (RAG)

Multiple search services for different data domains:

| Search Service | Content | Use Case |
|----------------|---------|----------|
| Customer Search | Customer profiles | "Find John Smith on Oak Street" |
| Meter Search | Meter metadata | "Look up meter MTR-12345" |
| Asset Search | Equipment specs | "Find transformer specifications" |
| Document Search | Technical manuals | "How to maintain transformers" |

### Cortex Agent (Multi-Tool)

Orchestrates multiple AI capabilities:

```mermaid
flowchart TD
    subgraph Agent["GRID INTELLIGENCE AGENT"]
        USER["User: Show high-risk transformers<br/>near substation 5"]
        TOOL["Tool Selection"]
        
        USER --> TOOL
        
        TOOL --> ANA["Analyst<br/>(SQL)"]
        TOOL --> SRC["Search<br/>(RAG)"]
        TOOL --> PRO["Procedures<br/>(Cascade)"]
        TOOL --> EXT["External<br/>APIs"]
    end
    
    style Agent fill:#37474f,color:#fff
    style ANA fill:#1565c0,color:#fff
    style SRC fill:#2e7d32,color:#fff
    style PRO fill:#ef6c00,color:#fff
    style EXT fill:#7b1fa2,color:#fff
```

---

## Deployment Architecture

### Five Deployment Paths

All paths deploy identical infrastructure - choose based on your team's preferences:

```mermaid
flowchart TD
    REPO["flux-utility-solutions/"]
    
    REPO --> SQL["SQL Scripts<br/><i>Manual Control</i>"]
    REPO --> NB["Notebooks<br/><i>Workshop POCs</i>"]
    REPO --> GIT["Git Integration<br/><i>GitOps Workflows</i>"]
    REPO --> CLI["CLI<br/><i>Quick Start</i>"]
    REPO --> TF["Terraform<br/><i>Enterprise Multi-env</i>"]
    
    style REPO fill:#37474f,color:#fff
    style SQL fill:#1565c0,color:#fff
    style NB fill:#ef6c00,color:#fff
    style GIT fill:#2e7d32,color:#fff
    style CLI fill:#c62828,color:#fff
    style TF fill:#7b1fa2,color:#fff
```

| Path | Best For | Key Feature |
|------|----------|-------------|
| **SQL Scripts** | Learning, auditing | Full visibility into each step |
| **Notebooks** | POC workshops | Interactive, documented execution |
| **Git Integration** | Modern DevOps | EXECUTE IMMEDIATE FROM repository |
| **CLI** | Quick demos | Single-command deployment |
| **Terraform** | Enterprise | Multi-environment, state management |

### Deployment Phases

Regardless of path chosen, deployment follows these phases:

```mermaid
flowchart LR
    subgraph P1["PHASE 1-3: FOUNDATION"]
        A1["Infrastructure<br/>Database, Schemas"]
        A2["Reference Data<br/>Substations, Circuits"]
        A3["Core Tables<br/>Transformers, Meters"]
    end
    
    subgraph P2["PHASE 4-6: ANALYTICS"]
        B1["Views & Analytics<br/>Dynamic Tables"]
        B2["Streamlit Apps<br/>Dashboards"]
        B3["Notebooks<br/>Setup, Demos"]
    end
    
    subgraph P3["PHASE 7-10: FINALIZATION"]
        C1["ML Features<br/>Model Registry"]
        C2["Security<br/>RBAC Roles"]
        C3["Seed Data<br/>Sample Loading"]
        C4["Validation<br/>Verification"]
    end
    
    P1 --> P2 --> P3
    
    style P1 fill:#1565c0,color:#fff
    style P2 fill:#ef6c00,color:#fff
    style P3 fill:#2e7d32,color:#fff
```

---

## Security Model

### Role-Based Access Control (RBAC)

```mermaid
flowchart TD
    AA["ACCOUNTADMIN"]
    FA["FLUX_ADMIN<br/><i>Full ownership</i>"]
    
    FU["FLUX_USER<br/><i>Analytics</i>"]
    FE["FLUX_ETL<br/><i>Data Load</i>"]
    FS["FLUX_SERVICE<br/><i>SPCS</i>"]
    
    FAN["FLUX_ANALYST<br/><i>Cortex Analyst access</i>"]
    
    AA --> FA
    FA --> FU
    FA --> FE
    FA --> FS
    FU --> FAN
    
    style AA fill:#b71c1c,color:#fff
    style FA fill:#1565c0,color:#fff
    style FU fill:#2e7d32,color:#fff
    style FE fill:#ef6c00,color:#fff
    style FS fill:#6a1b9a,color:#fff
    style FAN fill:#00838f,color:#fff
```

### Permission Matrix

| Role | Database | Warehouse | Semantic Views | Search | Agents |
|------|----------|-----------|----------------|--------|--------|
| Admin | OWNERSHIP | OPERATE | ALL | ALL | ALL |
| User | USAGE | USAGE | SELECT | QUERY | USAGE |
| Analyst | USAGE | USAGE | SELECT | QUERY | - |
| ETL | MODIFY | USAGE | - | - | - |
| Service | USAGE | USAGE | - | - | USAGE |

---

## Scalability

### Data Volume Guidelines

| Table Type | Expected Scale | Optimization |
|------------|----------------|--------------|
| AMI Readings | Billions of rows | Clustered by (timestamp, meter_id) |
| Transformer Load | Hundreds of millions | Clustered by (transformer_id, hour) |
| Customer Data | Hundreds of thousands | Cortex Search indexed |
| Asset Metadata | Thousands | Standard tables |

### Warehouse Sizing Recommendations

| Workload | Warehouse Size | Notes |
|----------|----------------|-------|
| Interactive queries | X-SMALL to SMALL | Auto-suspend 60s |
| AMI aggregations | MEDIUM to LARGE | Date-range queries |
| ML training | MEDIUM with GPU | Model fitting |
| Search indexing | SMALL | Background refresh |
| Bulk data loading | SMALL to MEDIUM | Parallel ingestion |

---

## Integration Points

### External Integrations

| Integration | Purpose | Implementation |
|-------------|---------|----------------|
| GitHub | Version control, GitOps | Git repository stage |
| Weather APIs | Outage correlation | External access integration |
| GIS Systems | Geospatial data | H3 hexagonal indexing |
| SCADA | Real-time operations | Streaming ingestion |

### Internal Snowflake Features

| Feature | Usage |
|---------|-------|
| Dynamic Tables | Declarative data pipelines |
| Streams & Tasks | CDC and scheduling |
| Snowpipe | Automated data ingestion |
| Model Registry | ML model versioning |
| Stages | File storage and Git integration |

---

## Getting Started

1. **Choose your deployment path** based on team preferences
2. **Clone the repository** and review documentation
3. **Configure connection** using Snow CLI or Terraform
4. **Deploy infrastructure** following the chosen path
5. **Load seed data** for immediate exploration
6. **Explore applications** - Streamlit apps and notebooks

See [README.md](../README.md) for quick start instructions.

---

## Additional Resources

| Document | Description |
|----------|-------------|
| [DATA_MODEL.md](./DATA_MODEL.md) | Detailed schema documentation |
| [CORTEX_GUIDE.md](./CORTEX_GUIDE.md) | AI features configuration |
| [TERRAFORM_GUIDE.md](./TERRAFORM_GUIDE.md) | Infrastructure as Code guide |
| [DEPLOYMENT.md](./DEPLOYMENT.md) | Step-by-step deployment |
