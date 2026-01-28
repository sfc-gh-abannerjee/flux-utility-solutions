# Flux Utility Solutions - Small Seed Data

Quick-start dataset for demos and POCs (~1GB total).

## Contents

| File | Table | Rows | Size |
|------|-------|------|------|
| substations.parquet | SUBSTATIONS | 98 | ~10 KB |
| transformers.parquet | TRANSFORMER_METADATA | 5,000 | ~500 KB |
| customers.parquet | CUSTOMERS_MASTER_DATA | 25,000 | ~3 MB |
| ami_readings.parquet | AMI_INTERVAL_READINGS | 672,000 | ~50 MB |

## Usage

### Generate the data

```bash
cd generators
pip install -r requirements.txt
python generate_all.py --size small --output ../seed_data/small
```

### Load to Snowflake

```bash
# Using the loader script
python generators/load_seed_data.py --source small --database FLUX_DEV

# Or using Snowflake CLI
snow sql -q "PUT file://seed_data/small/*.parquet @FLUX_DEV.PRODUCTION.DATA_STAGE"
```

## Data Characteristics

- **Duration**: 7 days of AMI data
- **Load time**: ~2 minutes
- **Use case**: Quick demos, Cortex testing, development

## Notes

- Parquet files are not committed to git (too large)
- Run generators or download from releases
- Manifest.json lists files and target tables
