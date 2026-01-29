# Seed Data Loading Guide

This guide explains how to load seed data into your Flux Ops Center deployment. The repository includes bundled sample data that can be loaded into any Snowflake account without requiring access to any external data sources.

## Data Options

| Option | Size | Best For |
|--------|------|----------|
| **CSV (Minimal)** | ~100 KB | Quick testing, CI/CD |
| **Parquet (Production)** | ~25 MB | Full demos, realistic scale |
| **Generated (Full Scale)** | ~10+ GB | Production testing, ML training |

---

## Production Seed Data (Parquet)

The repository includes production-scale sample data in `seed_data/parquet/`:

| Category | Table | Rows | Description |
|----------|-------|------|-------------|
| **Reference** | SUBSTATIONS | 275 | Grid substations |
| | CIRCUIT_METADATA | 8,842 | Distribution circuits |
| | TRANSFORMER_METADATA | 91,554 | Distribution transformers |
| | GRID_POLES_INFRASTRUCTURE | 62,038 | Pole infrastructure |
| | HOUSTON_WEATHER_HOURLY | 4,464 | Weather data |
| | ERCOT_LMP_HOUSTON_ZONE | 45,213 | Energy pricing |
| | POWER_QUALITY_READINGS | 10,000 | PQ events |
| **Operational** | SAP_WORK_ORDERS | 250,488 | Maintenance work orders |
| | OUTAGE_EVENTS | 34,252 | Historical outages |
| **Samples** | METER_INFRASTRUCTURE | 10,000 | Smart meters (sample) |
| | CUSTOMERS_MASTER_DATA | 11,849 | Customers (sample) |

### Loading Parquet Data

**Method 1: Git Integration (Recommended)**

```sql
-- First, set up Git integration (run once)
-- See git_deploy/setup_git_integration.sql

-- Then load seed data directly from repo
EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/scripts/51_load_seed_data.sql
  USING (database => 'FLUX_PROD', schema => 'PRODUCTION');
```

**Method 2: Snowflake Notebook**

Import `notebooks/setup/02_load_seed_data.ipynb` into Snowsight and run interactively.

**Method 3: Snow CLI**

```bash
snow sql -f scripts/51_load_seed_data.sql \
    -D "database=FLUX_PROD" \
    -D "schema=PRODUCTION"
```

---

## Minimal Seed Data (CSV)

The repository includes sample data files in `seed_data/csv/`:

| File | Description | Rows |
|------|-------------|------|
| `substations.csv` | Electrical substations with location and capacity data | 50 |
| `transformers.csv` | Distribution transformers with load metrics | 100 |
| `meters.csv` | Smart meter infrastructure with geographic data | 100 |
| `customers.csv` | Customer master data with service information | 100 |

This sample data provides enough records to demonstrate all features of the Flux Ops Center while keeping file sizes small for git.

## Loading Methods

### Method 1: Automatic Loading (Recommended)

The deployment scripts automatically load seed data. Simply run:

```bash
# Full deployment with seed data
./cli/deploy.sh --env dev

# Or use quickstart
./cli/quickstart.sh --database FLUX_OPS --warehouse COMPUTE_WH
```

### Method 2: Standalone Seed Data Loader

Load seed data into an existing deployment:

```bash
./cli/load_seed_data.sh \
    --database FLUX_OPS \
    --warehouse COMPUTE_WH
```

### Method 3: Manual SQL Loading

1. **Upload CSV files to a stage:**

```bash
# Using Snowflake CLI
snow stage copy seed_data/csv/substations.csv @FLUX_OPS.PRODUCTION.SEED_DATA_STAGE/substations/ --overwrite
snow stage copy seed_data/csv/transformers.csv @FLUX_OPS.PRODUCTION.SEED_DATA_STAGE/transformers/ --overwrite
snow stage copy seed_data/csv/meters.csv @FLUX_OPS.PRODUCTION.SEED_DATA_STAGE/meters/ --overwrite
snow stage copy seed_data/csv/customers.csv @FLUX_OPS.PRODUCTION.SEED_DATA_STAGE/customers/ --overwrite
```

2. **Run the loading script:**

```bash
snow sql -f scripts/50_load_seed_data.sql \
    -D "database='FLUX_OPS'" \
    -D "warehouse='COMPUTE_WH'"
```

## PostgreSQL Seed Data

For hybrid deployments with PostgreSQL:

```bash
# Create schema and load data
./seed_data/postgresql/load_postgresql.sh \
    --host localhost \
    --port 5432 \
    --database flux_ops \
    --user postgres
```

Or manually:

```bash
# Create schema
psql -h localhost -U postgres -d flux_ops -f seed_data/postgresql/01_schema.sql

# Load data
psql -h localhost -U postgres -d flux_ops -f seed_data/postgresql/02_load_data.sql
```

## AMI Time-Series Data

The seed data loading process automatically generates 7 days of synthetic AMI (Advanced Metering Infrastructure) readings. These readings:

- Cover hourly intervals for the past 7 days
- Include realistic consumption patterns (morning/evening peaks, overnight lows)
- Are distributed across residential, commercial, and industrial segments
- Include quality flags (VALID/ESTIMATED)

To regenerate AMI data with different parameters:

```bash
snow sql -f scripts/51_generate_ami_sample.sql \
    -D "database='FLUX_OPS'" \
    -D "warehouse='COMPUTE_WH'" \
    -D "days=30"  # Generate 30 days instead of 7
```

## Generating Larger Datasets

For larger datasets beyond the bundled samples, use the Flux Data Forge:

### Option 1: Python Generators

```bash
python3 generators/generate_all.py \
    --database FLUX_OPS \
    --connection default \
    --scale medium  # small, medium, large
```

### Option 2: Flux Data Forge SPCS Service

The SPCS-deployed Data Forge can generate millions of records:

```sql
-- Generate 100,000 meters
CALL APPLICATIONS.DATA_FORGE.GENERATE_METERS(100000);

-- Generate 1 year of AMI readings
CALL APPLICATIONS.DATA_FORGE.GENERATE_AMI_READINGS('2024-01-01', '2024-12-31');
```

## Validation

After loading seed data, verify the deployment:

```bash
# Run validation script
snow sql -f scripts/99_validate_deployment.sql \
    -D "database='FLUX_OPS'"
```

Expected output:
```
SUBSTATIONS: 50 rows
TRANSFORMER_METADATA: 100 rows
METER_INFRASTRUCTURE: 100 rows
CUSTOMERS_MASTER_DATA: 100 rows
AMI_READINGS: ~16,800 rows (100 meters × 168 hours)
```

## Troubleshooting

### CSV Upload Fails

If `snow stage copy` fails, try using SnowSQL PUT:

```sql
PUT file://seed_data/csv/substations.csv @SEED_DATA_STAGE/substations/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
```

### COPY INTO Errors

Check for data type mismatches:

```sql
-- View load errors
SELECT * FROM TABLE(VALIDATE(SUBSTATIONS, JOB_ID => '_last'));
```

### Missing Tables

Ensure infrastructure scripts ran first:

```bash
snow sql -f scripts/01_database_infrastructure.sql -D "database='FLUX_OPS'" -D "warehouse='COMPUTE_WH'"
snow sql -f scripts/03_substations_transformers.sql -D "database='FLUX_OPS'" -D "warehouse='COMPUTE_WH'"
```

## Data Dictionary

### SUBSTATIONS
| Column | Type | Description |
|--------|------|-------------|
| SUBSTATION_ID | VARCHAR | Unique identifier (e.g., SUB-0001) |
| SUBSTATION_NAME | VARCHAR | Human-readable name |
| LATITUDE | FLOAT | Geographic latitude |
| LONGITUDE | FLOAT | Geographic longitude |
| CAPACITY_MVA | NUMBER | Maximum capacity in MVA |
| REGION | VARCHAR | Service region |
| VOLTAGE_LEVEL | VARCHAR | Primary voltage (e.g., 138 kV) |
| COMMISSIONED_DATE | DATE | Date commissioned |
| OPERATIONAL_STATUS | VARCHAR | Current status |
| SUBSTATION_TYPE | VARCHAR | Transmission/Distribution |

### TRANSFORMER_METADATA
| Column | Type | Description |
|--------|------|-------------|
| TRANSFORMER_ID | VARCHAR | Unique identifier |
| SUBSTATION_ID | VARCHAR | Parent substation |
| CIRCUIT_ID | VARCHAR | Associated circuit |
| RATED_KVA | NUMBER | Rated capacity in kVA |
| HEALTH_SCORE | FLOAT | AI-predicted health (0-100) |
| METER_COUNT | NUMBER | Connected meters |

### METER_INFRASTRUCTURE
| Column | Type | Description |
|--------|------|-------------|
| METER_ID | VARCHAR | Unique identifier |
| METER_TYPE | VARCHAR | AMI, AMR, or Standard |
| CUSTOMER_SEGMENT_ID | VARCHAR | RESIDENTIAL, COMMERCIAL, INDUSTRIAL |
| HEALTH_SCORE | FLOAT | Device health (0-100) |

### CUSTOMERS_MASTER_DATA
| Column | Type | Description |
|--------|------|-------------|
| CUSTOMER_ID | VARCHAR | Unique identifier |
| PRIMARY_METER_ID | VARCHAR | Associated meter |
| CUSTOMER_SEGMENT | VARCHAR | Rate class/segment |
| ACCOUNT_STATUS | VARCHAR | ACTIVE, INACTIVE, etc. |
