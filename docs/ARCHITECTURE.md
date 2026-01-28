# Flux Utility Solutions - Architecture

System architecture and design decisions.

## Overview

Flux Utility Solutions is a **4-layer hybrid platform** for utility grid analytics:

```
┌─────────────────────────────────────────────────────────────────┐
│                     APPLICATION LAYER                            │
│    Flux Ops Center (Streamlit) │ Grid Intelligence Agent        │
├─────────────────────────────────────────────────────────────────┤
│                      ANALYTICS LAYER                             │
│  Snowflake │ 7.1B AMI rows │ Semantic Views │ Cortex AI         │
├─────────────────────────────────────────────────────────────────┤
│                      STREAMING LAYER                             │
│            CDC Sync │ PostgreSQL → Snowflake                     │
├─────────────────────────────────────────────────────────────────┤
│                    TRANSACTIONAL LAYER                           │
│    PostgreSQL 17.7 │ <20ms latency │ Real-time operations       │
└─────────────────────────────────────────────────────────────────┘
```

## Layer Details

### Layer 1: Transactional (PostgreSQL)

**Purpose**: Real-time operations with <20ms latency

| Component | Description |
|-----------|-------------|
| PostgreSQL 17.7 | Native Snowflake PostgreSQL instance |
| Schemas | operations, scada, work_orders |
| Latency | <20ms for real-time queries |
| Retention | 24 hours (hot data) |

**Tables**:
- `meter_readings_realtime` - Last 24h readings
- `outage_events` - Active outage tracking
- `work_orders.field_orders` - Field service management

### Layer 2: Streaming (CDC)

**Purpose**: Continuous data sync from PostgreSQL to Snowflake

| Component | Description |
|-----------|-------------|
| CDC Type | Incremental change capture |
| Frequency | 1-15 minutes depending on table |
| Pattern | Staging tables → MERGE into production |

### Layer 3: Analytics (Snowflake)

**Purpose**: Large-scale analytics and AI workloads

| Component | Scale | Description |
|-----------|-------|-------------|
| AMI Readings | 7.1B rows | 15-minute interval data |
| Transformers | 211M rows | Hourly load data |
| Customers | 686K | Master profiles |
| Meters | 597K | Smart meter metadata |

**Schemas**:
- `PRODUCTION` - Core data tables
- `APPLICATIONS` - Semantic views, agents, services

### Layer 4: Application (SPCS)

**Purpose**: User-facing applications and services

| Component | Description |
|-----------|-------------|
| Flux Ops Center | Streamlit dashboard |
| Grid Intelligence Agent | Cortex AI assistant |
| Data Forge | ETL and data generation |

## AI Architecture

### Cortex Analyst

```
User Question
     │
     ▼
┌─────────────────┐
│ Semantic View   │◄── utility_semantic_model.yaml
│ (Owner's Rights)│    30 tables, relationships
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ SQL Generation  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Query Execution │
└────────┬────────┘
         │
         ▼
    Response
```

### Cortex Search (RAG)

```
┌─────────────────────────────────────────────────────┐
│                 SEARCH SERVICES                      │
├─────────────────┬─────────────────┬─────────────────┤
│ Customer Search │ Meter Search    │ Tech Docs       │
│ 686K profiles   │ 597K meters     │ 20K chunks      │
│ Name, Address   │ ID, Location    │ Manuals, Guides │
└────────┬────────┴────────┬────────┴────────┬────────┘
         │                 │                 │
         └─────────────────┼─────────────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │ Grid Intel Agent│
                  │ Tool Selection  │
                  └─────────────────┘
```

### Agent Tool Selection

| Question Type | Tool | Examples |
|--------------|------|----------|
| Aggregations | Cortex Analyst | "Total consumption", "Average load" |
| Rankings | Cortex Analyst | "Top 10 customers", "Worst transformers" |
| Lookups | Cortex Search | "Find John Smith", "Meter MTR-12345" |
| Technical | Cortex Search | "How to maintain transformer" |

## Data Model

### Entity Relationships

```
SUBSTATIONS (98)
     │
     ▼
CIRCUITS (73) ──────────► CIRCUIT_METADATA
     │
     ▼
TRANSFORMERS (91K) ─────► TRANSFORMER_HOURLY_LOAD (211M)
     │
     ▼
METERS (597K) ──────────► AMI_READINGS (7.1B)
     │
     ▼
CUSTOMERS (686K)
```

### Key Tables

| Table | Rows | Purpose |
|-------|------|---------|
| AMI_INTERVAL_READINGS | 7.1B | Raw 15-min readings |
| AMI_READINGS_FINAL | 7.1B | Enhanced with sags/outages |
| TRANSFORMER_HOURLY_LOAD | 211M | Hourly transformer loading |
| TRANSFORMER_METADATA | 91K | Fleet specifications |
| CUSTOMERS_MASTER_DATA | 686K | Customer profiles |
| METER_INFRASTRUCTURE | 597K | Meter specifications |

## Security Model

### RBAC Hierarchy

```
ACCOUNTADMIN
     │
     ▼
FLUX_ADMIN_ROLE ─────────┬─────────┐
     │                   │         │
     ▼                   ▼         ▼
FLUX_USER_ROLE    FLUX_ETL_ROLE   FLUX_SERVICE_ROLE
     │
     ▼
FLUX_ANALYST_ROLE
```

### Permissions

| Role | Database | Warehouse | Semantic Views | Agents |
|------|----------|-----------|----------------|--------|
| Admin | OWNERSHIP | OPERATE | ALL | ALL |
| User | USAGE | USAGE | SELECT | USAGE |
| Analyst | USAGE | USAGE | SELECT | - |
| ETL | USAGE | USAGE | - | - |

## Deployment Architecture

### 5 Deployment Paths

```
                    ┌─────────────────┐
                    │  flux-utility-  │
                    │   solutions/    │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │          │         │         │          │
        ▼          ▼         ▼         ▼          ▼
   ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
   │  SQL   │ │Notebook│ │  Git   │ │  CLI   │ │Terraform│
   │Scripts │ │        │ │        │ │        │ │        │
   └────────┘ └────────┘ └────────┘ └────────┘ └────────┘
```

All paths deploy identical infrastructure with zero delta.

## Performance Considerations

### Query Optimization

| Pattern | Optimization |
|---------|-------------|
| AMI aggregations | Clustered by (TIMESTAMP, METER_ID) |
| Transformer lookups | Clustered by (TRANSFORMER_ID) |
| Customer search | Cortex Search index |
| Time-series | Micro-partitions by date |

### Warehouse Sizing

| Workload | Recommended Size |
|----------|------------------|
| Interactive queries | SMALL |
| AMI aggregations | MEDIUM-LARGE |
| Search index refresh | SMALL |
| ML training | GPU (FLUX_ML_POOL) |
