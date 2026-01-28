# Flux Utility Solutions - Full Seed Data

Production-scale dataset for realistic testing (~10GB total).

## Contents

| File | Table | Rows | Size |
|------|-------|------|------|
| substations.parquet | SUBSTATIONS | 98 | ~10 KB |
| transformers.parquet | TRANSFORMER_METADATA | 91,000 | ~9 MB |
| customers.parquet | CUSTOMERS_MASTER_DATA | 686,000 | ~80 MB |
| meters.parquet | METER_INFRASTRUCTURE | 597,000 | ~70 MB |
| ami_readings.parquet | AMI_INTERVAL_READINGS | 28,800,000 | ~2 GB |

## Usage

### Generate the data

```bash
cd generators
pip install -r requirements.txt

# Full generation takes ~30 minutes
python generate_all.py --size full --output ../seed_data/full
```

### Load to Snowflake

```bash
# Using the loader script
python generators/load_seed_data.py --source full --database FLUX_PROD

# Or stage and COPY
snow sql -q "PUT file://seed_data/full/*.parquet @FLUX_PROD.RAW.DATA_STAGE"
snow sql -f scripts/load_staged_data.sql
```

## Data Characteristics

- **Duration**: 30 days of AMI data
- **Transformers**: 91,000 (matches production)
- **Customers**: 686,000 (matches production)
- **Load time**: ~15 minutes (with LARGE warehouse)
- **Use case**: Performance testing, ML training, production validation

## Production Comparison

| Metric | This Dataset | Production |
|--------|--------------|------------|
| Substations | 98 | 98 |
| Transformers | 91,000 | 91,554 |
| Customers | 686,000 | 686,359 |
| AMI Rows | 28.8M | 7.1B |

## Notes

- Full AMI data (7.1B rows) requires Snowflake ingestion
- Parquet files are not committed to git
- Download from GitHub Releases or generate locally
