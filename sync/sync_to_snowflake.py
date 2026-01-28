"""
PostgreSQL to Snowflake Sync - Operational Events

Syncs real-time operational data from PostgreSQL back to Snowflake
for analytics and historical tracking.

This handles:
- Outage events created in the operations center
- Work orders and field updates
- Real-time telemetry aggregations

Usage:
    python sync_to_snowflake.py --tables outages,work_orders
    python sync_to_snowflake.py --incremental --since "2024-01-01"
"""

import os
import sys
import argparse
import logging
from datetime import datetime, timedelta
from typing import List, Optional

import pandas as pd
import snowflake.connector
from snowflake.connector.pandas_tools import write_pandas
import psycopg2

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


# =============================================================================
# Configuration
# =============================================================================

SNOWFLAKE_CONFIG = {
    'account': os.getenv('SNOWFLAKE_ACCOUNT'),
    'user': os.getenv('SNOWFLAKE_USER'),
    'password': os.getenv('SNOWFLAKE_PASSWORD'),
    'warehouse': os.getenv('SNOWFLAKE_WAREHOUSE', 'FLUX_WH'),
    'database': os.getenv('SNOWFLAKE_DATABASE', 'FLUX_PROD'),
    'schema': os.getenv('SNOWFLAKE_SCHEMA', 'PRODUCTION'),
}

POSTGRES_CONFIG = {
    'host': os.getenv('POSTGRES_HOST'),
    'port': os.getenv('POSTGRES_PORT', 5432),
    'database': os.getenv('POSTGRES_DATABASE', 'postgres'),
    'user': os.getenv('POSTGRES_USER', 'application'),
    'password': os.getenv('POSTGRES_PASSWORD'),
}

# Tables to sync back to Snowflake
SYNC_TABLES = {
    'outages': {
        'postgres_table': 'outages',
        'snowflake_table': 'OUTAGE_EVENTS_STREAM',
        'timestamp_column': 'updated_at',
        'primary_key': 'outage_id',
    },
    'work_orders': {
        'postgres_table': 'work_orders',
        'snowflake_table': 'WORK_ORDERS_STREAM',
        'timestamp_column': 'updated_at',
        'primary_key': 'work_order_id',
    },
    'telemetry': {
        'postgres_table': 'transformer_telemetry',
        'snowflake_table': 'TRANSFORMER_TELEMETRY_STREAM',
        'timestamp_column': 'reading_time',
        'primary_key': 'telemetry_id',
    },
}


# =============================================================================
# Database Connections
# =============================================================================

def get_snowflake_connection():
    """Create Snowflake connection."""
    return snowflake.connector.connect(**SNOWFLAKE_CONFIG)


def get_postgres_connection():
    """Create PostgreSQL connection."""
    return psycopg2.connect(**POSTGRES_CONFIG)


# =============================================================================
# Sync Functions
# =============================================================================

def fetch_from_postgres(
    table_config: dict,
    since: Optional[datetime] = None
) -> pd.DataFrame:
    """Fetch data from PostgreSQL, optionally since a timestamp."""
    pg_table = table_config['postgres_table']
    ts_col = table_config['timestamp_column']
    
    query = f"SELECT * FROM {pg_table}"
    params = []
    
    if since:
        query += f" WHERE {ts_col} >= %s"
        params.append(since)
    
    query += f" ORDER BY {ts_col}"
    
    logger.info(f"Fetching from PostgreSQL: {pg_table}")
    
    conn = get_postgres_connection()
    try:
        df = pd.read_sql(query, conn, params=params or None)
        logger.info(f"Fetched {len(df)} rows")
        return df
    finally:
        conn.close()


def get_last_sync_timestamp(table_config: dict) -> Optional[datetime]:
    """Get the last synced timestamp from Snowflake."""
    sf_table = table_config['snowflake_table']
    ts_col = table_config['timestamp_column']
    
    query = f"SELECT MAX({ts_col}) as last_sync FROM {sf_table}"
    
    conn = get_snowflake_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(query)
        result = cursor.fetchone()
        return result[0] if result and result[0] else None
    except Exception as e:
        # Table might not exist yet
        logger.warning(f"Could not get last sync: {e}")
        return None
    finally:
        conn.close()


def sync_to_snowflake(table_name: str, df: pd.DataFrame, table_config: dict):
    """Sync DataFrame to Snowflake using MERGE."""
    sf_table = table_config['snowflake_table']
    pk = table_config['primary_key']
    
    if df.empty:
        logger.info(f"No new records for {sf_table}")
        return
    
    # Uppercase column names for Snowflake
    df.columns = [c.upper() for c in df.columns]
    
    conn = get_snowflake_connection()
    try:
        # Use write_pandas for efficient loading
        success, num_chunks, num_rows, output = write_pandas(
            conn,
            df,
            sf_table,
            database=SNOWFLAKE_CONFIG['database'],
            schema=SNOWFLAKE_CONFIG['schema'],
            auto_create_table=True,
            overwrite=False,
        )
        
        if success:
            logger.info(f"Synced {num_rows} rows to {sf_table}")
        else:
            logger.error(f"Failed to sync to {sf_table}")
            
    finally:
        conn.close()


def sync_table(
    table_name: str,
    incremental: bool = True,
    since: Optional[datetime] = None
):
    """Sync a single table from PostgreSQL to Snowflake."""
    if table_name not in SYNC_TABLES:
        logger.error(f"Unknown table: {table_name}")
        return False
    
    config = SYNC_TABLES[table_name]
    
    try:
        # Determine start time for incremental sync
        if incremental and not since:
            since = get_last_sync_timestamp(config)
            if since:
                logger.info(f"Incremental sync from {since}")
        
        # Fetch from PostgreSQL
        df = fetch_from_postgres(config, since)
        
        # Sync to Snowflake
        sync_to_snowflake(table_name, df, config)
        
        return True
    except Exception as e:
        logger.error(f"Error syncing {table_name}: {e}")
        return False


def full_sync(incremental: bool = True, since: Optional[datetime] = None):
    """Sync all tables."""
    results = {}
    for table_name in SYNC_TABLES:
        results[table_name] = sync_table(table_name, incremental, since)
    return results


# =============================================================================
# CLI
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description='Sync PostgreSQL to Snowflake')
    parser.add_argument('--tables', type=str, help='Comma-separated table names')
    parser.add_argument('--full-sync', action='store_true', help='Sync all tables')
    parser.add_argument('--incremental', action='store_true', help='Only sync new records')
    parser.add_argument('--since', type=str, help='Sync since timestamp (YYYY-MM-DD)')
    
    args = parser.parse_args()
    
    since = None
    if args.since:
        since = datetime.fromisoformat(args.since)
    
    if args.full_sync:
        results = full_sync(args.incremental, since)
        for table, success in results.items():
            status = '✓' if success else '✗'
            print(f"{status} {table}")
    elif args.tables:
        tables = args.tables.split(',')
        for table in tables:
            success = sync_table(table.strip(), args.incremental, since)
            status = '✓' if success else '✗'
            print(f"{status} {table}")
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
