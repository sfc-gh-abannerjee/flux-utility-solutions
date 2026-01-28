# Flux Data Forge - Streaming Synthetic Data Generator

SPCS application for generating realistic utility data at scale. Streams data to Snowflake tables, internal stages, or external cloud storage.

## Features

- **AMI Readings**: 15-minute interval smart meter data with realistic load curves
- **Transformer Telemetry**: Temperature, load, oil level, DGA indicators
- **Outage Events**: Weather-correlated patterns with restoration times
- **Configurable Throughput**: 100 to 100,000 records/second
- **Multiple Outputs**: Snowflake tables, internal stages, external stages (S3/GCS/Azure)

## Quick Start

### Local Development

```bash
pip install -r requirements.txt
python -m src.main
```

### Deploy to SPCS

```sql
-- 1. Create image repository
CREATE IMAGE REPOSITORY IF NOT EXISTS {{ database }}.{{ schema }}.data_forge_repo;

-- 2. Create internal stage for output
CREATE STAGE IF NOT EXISTS {{ database }}.{{ schema }}.DATA_FORGE_STAGE;

-- 3. Deploy service
CREATE SERVICE {{ database }}.{{ schema }}.FLUX_DATA_FORGE_SERVICE
  IN COMPUTE POOL flux_compute_pool
  FROM SPECIFICATION_FILE = 'service.yaml'
  EXTERNAL_ACCESS_INTEGRATIONS = (allow_all_access_integration);
```

### Docker

```bash
docker build -t flux-data-forge:latest .
docker run -p 8080:8080 flux-data-forge:latest
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/status` | GET | Generator status and metrics |
| `/start` | POST | Start data generation |
| `/stop` | POST | Stop data generation |
| `/preview/{type}` | GET | Preview generated data |

### Start Generation

```bash
curl -X POST http://localhost:8080/start \
  -H "Content-Type: application/json" \
  -d '{
    "data_type": "ami",
    "records_per_second": 1000,
    "duration_seconds": 300,
    "output_snowflake": true,
    "output_stage": false
  }'
```

### Check Status

```bash
curl http://localhost:8080/status
```

Response:
```json
{
  "is_running": true,
  "records_generated": 150000,
  "batches_written": 15,
  "uptime_seconds": 150.5,
  "records_per_second": 997.2,
  "errors": []
}
```

## Data Types

### AMI Readings

| Column | Type | Description |
|--------|------|-------------|
| reading_id | UUID | Unique identifier |
| meter_id | VARCHAR | Meter ID (MTR-XXXXXX) |
| transformer_id | VARCHAR | Parent transformer |
| reading_timestamp | TIMESTAMP | Reading time |
| kwh_reading | FLOAT | Energy consumption |
| voltage | FLOAT | Line voltage |
| power_factor | FLOAT | Power factor |
| quality_flag | VARCHAR | VALID, ANOMALY |

### Transformer Telemetry

| Column | Type | Description |
|--------|------|-------------|
| telemetry_id | UUID | Unique identifier |
| transformer_id | VARCHAR | Transformer ID |
| oil_temperature_f | FLOAT | Oil temperature |
| winding_temperature_f | FLOAT | Winding temperature |
| load_percentage | FLOAT | Current load % |
| hydrogen_ppm | INT | Dissolved hydrogen |
| health_score | FLOAT | Overall health (0-100) |

### Outage Events

| Column | Type | Description |
|--------|------|-------------|
| outage_id | UUID | Unique identifier |
| feeder_id | VARCHAR | Affected feeder |
| cause | VARCHAR | WEATHER, EQUIPMENT, etc |
| status | VARCHAR | ACTIVE, RESTORED |
| customers_affected | INT | Number of customers |

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `GENERATION_MODE` | streaming | streaming or batch |
| `RECORDS_PER_SECOND` | 1000 | Target throughput |
| `BATCH_SIZE` | 10000 | Records per write |
| `OUTPUT_SNOWFLAKE` | true | Write to tables |
| `OUTPUT_STAGE` | true | Write to stage |
| `STAGE_PATH` | @DATA_FORGE_STAGE | Output stage |

## Use Cases

1. **Demo Data Population**: Generate realistic data for demos
2. **Load Testing**: Stress test Snowflake ingestion pipelines
3. **ML Training Data**: Generate labeled data for model training
4. **CDC Simulation**: Simulate real-time data streams
