# Flux Utility Solutions - Data Generators

Generate synthetic utility data for demos and testing.

## Quick Start

```bash
# Install dependencies
pip install -r requirements.txt

# Generate small dataset (~1GB, 5 minutes)
python generate_all.py --size small

# Generate full dataset (~10GB, 30 minutes)
python generate_all.py --size full

# Load to Snowflake
python load_seed_data.py --source small --database FLUX_DEV
```

## Individual Generators

| Script | Output | Rows (small) | Rows (full) |
|--------|--------|--------------|-------------|
| `generate_substations.py` | substations.parquet | 98 | 98 |
| `generate_transformers.py` | transformers.parquet | 5,000 | 91,000 |
| `generate_customers.py` | customers.parquet | 25,000 | 686,000 |
| `generate_ami_sample.py` | ami_readings.parquet | 672,000 | 28.8M |

## Data Characteristics

### Substations
- Houston metropolitan area geographic distribution
- Types: TRANSMISSION (15), DISTRIBUTION (70), SWITCHING (13)
- Voltage levels: 345KV, 138KV, 69KV
- Commissioned dates: 1960-2020

### Transformers
- Health scores calculated from age, load, and maintenance
- Manufacturers: ABB, Siemens, GE, Eaton, etc.
- Rated KVA: 15 to 1000
- Geographic clustering by substation

### Customers
- Texas demographics and address patterns
- Segments: RESIDENTIAL (75%), COMMERCIAL (20%), INDUSTRIAL (5%)
- Cities weighted by population

### AMI Readings
- 15-minute intervals
- Load profiles by segment (residential, commercial, industrial)
- Seasonal variation (Texas summer peak)
- Weekend patterns for commercial

## Usage Examples

```bash
# Generate only transformers
python generate_transformers.py --count 10000 --output ../seed_data/custom/transformers.parquet

# Generate 90 days of AMI data for 500 meters
python generate_ami_sample.py --meters 500 --days 90 --output ami_90day.parquet
```
