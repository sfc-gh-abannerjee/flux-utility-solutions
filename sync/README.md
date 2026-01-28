# Flux Sync Scripts

Bidirectional sync between Snowflake and PostgreSQL for hybrid architecture.

## Architecture

```
┌─────────────────┐          ┌─────────────────┐
│   Snowflake     │          │   PostgreSQL    │
│                 │          │                 │
│  Analytics      │◄────────►│  Operations     │
│  7.1B rows      │  Sync    │  <20ms reads    │
│  ML training    │          │  Real-time ops  │
└─────────────────┘          └─────────────────┘
```

## Scripts

### sync_to_postgres.py

Syncs master data from Snowflake to PostgreSQL for low-latency reads:
- Substations (98 records)
- Transformers (91K records)
- Customers (686K records)
- Meters (597K records)

```bash
# Sync all tables
python sync_to_postgres.py --full-sync

# Sync specific tables
python sync_to_postgres.py --tables substations,transformers

# Limit rows (for testing)
python sync_to_postgres.py --tables transformers --limit 1000
```

### sync_to_snowflake.py

Syncs operational events from PostgreSQL back to Snowflake for analytics:
- Outage events
- Work orders
- Telemetry aggregations

```bash
# Full sync
python sync_to_snowflake.py --full-sync

# Incremental sync (only new records)
python sync_to_snowflake.py --full-sync --incremental

# Sync since specific date
python sync_to_snowflake.py --tables outages --since 2024-01-01
```

## Configuration

Set environment variables:

```bash
# Snowflake
export SNOWFLAKE_ACCOUNT=your-account
export SNOWFLAKE_USER=your-user
export SNOWFLAKE_PASSWORD=your-password
export SNOWFLAKE_WAREHOUSE=FLUX_WH
export SNOWFLAKE_DATABASE=FLUX_PROD
export SNOWFLAKE_SCHEMA=PRODUCTION

# PostgreSQL
export POSTGRES_HOST=your-postgres-host.snowflake.app
export POSTGRES_PORT=5432
export POSTGRES_DATABASE=postgres
export POSTGRES_USER=application
export POSTGRES_PASSWORD=your-password
```

Or use a `.env` file:

```bash
source .env
python sync_to_postgres.py --full-sync
```

## Scheduling

For production, schedule syncs with cron or a task scheduler:

```bash
# Cron example: Sync master data every hour
0 * * * * cd /path/to/sync && python sync_to_postgres.py --full-sync

# Sync operational events every 5 minutes
*/5 * * * * cd /path/to/sync && python sync_to_snowflake.py --full-sync --incremental
```

## PostgreSQL Setup

The sync scripts assume PostGIS is installed for geospatial support:

```sql
-- Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- Tables are auto-created by sync scripts
-- But you can pre-create with indexes for performance:

CREATE TABLE substations (
    substation_id VARCHAR(100) PRIMARY KEY,
    substation_name VARCHAR(255),
    capacity_mva NUMERIC,
    voltage_level VARCHAR(50),
    status VARCHAR(50),
    location GEOGRAPHY(POINT, 4326)
);

CREATE INDEX idx_substations_location ON substations USING GIST (location);
```

## Error Handling

- Failed syncs are logged with error details
- Incremental sync tracks last successful timestamp
- Network errors trigger automatic retry (configure in production)

## Monitoring

Check sync status:

```sql
-- Snowflake: Check last sync time
SELECT MAX(UPDATED_AT) as last_sync 
FROM OUTAGE_EVENTS_STREAM;

-- PostgreSQL: Check row counts
SELECT 
    (SELECT COUNT(*) FROM substations) as substations,
    (SELECT COUNT(*) FROM transformers) as transformers,
    (SELECT COUNT(*) FROM customers) as customers;
```
