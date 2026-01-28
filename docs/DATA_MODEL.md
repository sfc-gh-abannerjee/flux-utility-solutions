# Flux Utility Solutions - Data Model

Complete data model reference for the Flux platform.

## Schema Overview

| Schema | Purpose | Objects |
|--------|---------|---------|
| PRODUCTION | Core data tables | 25+ tables |
| APPLICATIONS | AI/ML components | Semantic views, agents, services |
| SECRETS | Configuration | Secrets, API keys |

## Production Tables

### Grid Infrastructure

#### SUBSTATIONS
Distribution substations (98 records)

| Column | Type | Description |
|--------|------|-------------|
| SUBSTATION_ID | VARCHAR(50) | Primary key |
| SUBSTATION_NAME | VARCHAR(200) | Human-readable name |
| SUBSTATION_TYPE | VARCHAR(50) | DISTRIBUTION, TRANSMISSION |
| TOTAL_CAPACITY_MVA | NUMBER(10,2) | Total capacity |
| LATITUDE | FLOAT | Location |
| LONGITUDE | FLOAT | Location |

#### TRANSFORMER_METADATA
Distribution transformers (91K records)

| Column | Type | Description |
|--------|------|-------------|
| TRANSFORMER_ID | VARCHAR(50) | Primary key (XFMR-XXXXX) |
| SUBSTATION_ID | VARCHAR(50) | FK to SUBSTATIONS |
| CIRCUIT_ID | VARCHAR(50) | FK to CIRCUIT_METADATA |
| RATED_KVA | NUMBER(10,2) | Rated capacity |
| TRANSFORMER_ROLE | VARCHAR(50) | SERVICE, SPLIT, NETWORK |
| AGE_YEARS | NUMBER(5,2) | Installation age |
| HEALTH_SCORE | NUMBER(5,2) | 0-100 score |
| LOAD_UTILIZATION_PCT | FLOAT | Current utilization |
| METER_COUNT | NUMBER(10,0) | Meters served |

#### CIRCUIT_METADATA
Distribution circuits/feeders (73 records)

| Column | Type | Description |
|--------|------|-------------|
| CIRCUIT_ID | VARCHAR(50) | Primary key |
| CIRCUIT_NAME | VARCHAR(200) | Human-readable name |
| SUBSTATION_ID | VARCHAR(50) | FK to SUBSTATIONS |
| VOLTAGE_LEVEL_KV | NUMBER(4,2) | Operating voltage |
| TRANSFORMER_COUNT | NUMBER(10,0) | Transformers on circuit |
| METER_COUNT | NUMBER(10,0) | Meters on circuit |

### Metering

#### METER_INFRASTRUCTURE
Smart meters (597K records)

| Column | Type | Description |
|--------|------|-------------|
| METER_ID | VARCHAR(50) | Primary key (MTR-XXXXXXXX) |
| TRANSFORMER_ID | VARCHAR(50) | FK to TRANSFORMER_METADATA |
| SUBSTATION_ID | VARCHAR(50) | FK to SUBSTATIONS |
| CITY | VARCHAR(100) | Installation city |
| ZIP_CODE | VARCHAR(10) | ZIP code |
| COUNTY_NAME | VARCHAR(100) | County |
| CUSTOMER_SEGMENT_ID | VARCHAR(50) | Customer type |

#### AMI_INTERVAL_READINGS
15-minute interval readings (7.1B records)

| Column | Type | Description |
|--------|------|-------------|
| METER_ID | VARCHAR(50) | FK to METER_INFRASTRUCTURE |
| TIMESTAMP | TIMESTAMP_NTZ | Reading timestamp |
| USAGE_KWH | FLOAT | Energy consumption |
| VOLTAGE | NUMBER(6,2) | Voltage reading |
| POWER_FACTOR | NUMBER(4,3) | Power factor |

**Clustering**: (TIMESTAMP, METER_ID)

#### AMI_READINGS_FINAL
Enhanced readings with events (7.1B records)

| Column | Type | Description |
|--------|------|-------------|
| METER_ID | VARCHAR(50) | FK to METER_INFRASTRUCTURE |
| TIMESTAMP | TIMESTAMP_NTZ | Reading timestamp |
| USAGE_KWH | FLOAT | Original consumption |
| USAGE_KWH_ADJUSTED | FLOAT | Adjusted (0 during outages) |
| VOLTAGE | NUMBER(6,2) | Adjusted voltage |
| POWER_FACTOR | NUMBER(4,3) | Power factor |
| SAG_TYPE | VARCHAR(20) | Voltage sag type |
| VOLTAGE_DROP_AMOUNT | NUMBER(4,0) | Sag magnitude |
| OUTAGE_ID | VARCHAR(50) | Outage event ID |
| OUTAGE_CAUSE | VARCHAR(50) | Outage cause |

### Customers

#### CUSTOMERS_MASTER_DATA
Customer profiles (686K records)

| Column | Type | Description |
|--------|------|-------------|
| CUSTOMER_ID | VARCHAR(50) | Primary key (CUST-XXXXXXXX) |
| FULL_NAME | VARCHAR(200) | Customer name |
| SERVICE_ADDRESS | VARCHAR(500) | Service location |
| CITY | VARCHAR(100) | City |
| ZIP_CODE | VARCHAR(10) | ZIP code |
| SERVICE_COUNTY | VARCHAR(100) | County |
| CUSTOMER_SEGMENT | VARCHAR(50) | RESIDENTIAL, COMMERCIAL, INDUSTRIAL |
| INCOME_SEGMENT | VARCHAR(50) | LOW, MIDDLE, HIGH |
| ACCOUNT_STATUS | VARCHAR(20) | ACTIVE, INACTIVE |
| PRIMARY_METER_ID | VARCHAR(50) | FK to METER_INFRASTRUCTURE |
| AVG_MONTHLY_KWH | FLOAT | Average consumption |

### Aggregations

#### TRANSFORMER_HOURLY_LOAD
Hourly transformer loading (211M records)

| Column | Type | Description |
|--------|------|-------------|
| TRANSFORMER_ID | VARCHAR(50) | FK to TRANSFORMER_METADATA |
| LOAD_HOUR | TIMESTAMP_NTZ | Hour timestamp |
| LOAD_KW | NUMBER(10,2) | Load in kW |
| RATED_KVA | NUMBER(10,2) | Rated capacity |
| LOAD_FACTOR_PCT | FLOAT | Load / Capacity % |
| IS_OVERLOADED | BOOLEAN | Load > 100% |
| THERMAL_STRESS_CATEGORY | VARCHAR(20) | LOW, MODERATE, HIGH, CRITICAL |
| AMBIENT_TEMP_F | NUMBER(5,2) | Ambient temperature |

## Applications Objects

### Semantic View

**UTILITY_SEMANTIC_VIEW**

30-table semantic model for Cortex Analyst:
- AMI data (readings, aggregations)
- Transformers (metadata, loading)
- Customers (profiles, segments)
- Infrastructure (substations, circuits, meters)
- Operations (work orders, outages)

### Cortex Search Services

| Service | Records | Columns |
|---------|---------|---------|
| CUSTOMER_SEARCH_SERVICE | 686K | Name, address, segment |
| AMI_METADATA_SEARCH | 597K | Meter ID, location, transformer |
| TECHNICAL_MANUALS_SEARCH | 20K | Document chunks |

### Cortex Agents

| Agent | Tools | Purpose |
|-------|-------|---------|
| GRID_INTELLIGENCE_AGENT | Analyst, Search | General grid analytics |
| TRANSFORMER_ANALYST_AGENT | Analyst, Cascade | Asset health |
| CUSTOMER_SERVICE_AGENT | Search, Analyst | Customer lookup |

## Relationships

```
SUBSTATIONS
    ├── CIRCUIT_METADATA (1:N)
    └── TRANSFORMER_METADATA (1:N)
            └── METER_INFRASTRUCTURE (1:N)
                    ├── AMI_INTERVAL_READINGS (1:N)
                    └── CUSTOMERS_MASTER_DATA (1:1)

TRANSFORMER_METADATA
    └── TRANSFORMER_HOURLY_LOAD (1:N)
```

## Naming Conventions

| Object Type | Convention | Example |
|-------------|------------|---------|
| Database | FLUX_{ENV} | FLUX_PROD |
| Schema | UPPERCASE | PRODUCTION |
| Table | SNAKE_CASE | TRANSFORMER_METADATA |
| Column | SNAKE_CASE | LOAD_FACTOR_PCT |
| ID columns | {ENTITY}_ID | TRANSFORMER_ID |
| Roles | FLUX_{ENV}_{TYPE} | FLUX_PROD_ADMIN |
| Warehouses | FLUX_{ENV}_{TYPE}_WH | FLUX_PROD_LARGE_WH |
