"""
Snowflake to PostgreSQL Sync - Core Tables

Syncs operational data from Snowflake to PostgreSQL for low-latency reads.
PostgreSQL provides <20ms response for real-time operations while
Snowflake handles analytical queries.

Usage:
    python sync_to_postgres.py --tables substations,transformers
    python sync_to_postgres.py --full-sync
"""

import os
import sys
import argparse
import logging
from datetime import datetime
from typing import List, Optional

import pandas as pd
import snowflake.connector
import psycopg2
from psycopg2.extras import execute_values

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

# Tables to sync with their configurations
SYNC_TABLES = {
    'substations': {
        'snowflake_table': 'SUBSTATIONS',
        'postgres_table': 'substations',
        'primary_key': 'substation_id',
        'columns': [
            'substation_id', 'substation_name', 'capacity_mva', 
            'voltage_level', 'status', 'location'
        ],
        'geo_column': 'location',  # Requires PostGIS
    },
    'transformers': {
        'snowflake_table': 'TRANSFORMER_METADATA',
        'postgres_table': 'transformers',
        'primary_key': 'transformer_id',
        'columns': [
            'transformer_id', 'substation_id', 'kva_rating',
            'health_score', 'installation_date', 'status', 'location'
        ],
        'geo_column': 'location',
    },
    'customers': {
        'snowflake_table': 'CUSTOMERS_MASTER_DATA',
        'postgres_table': 'customers',
        'primary_key': 'customer_id',
        'columns': [
            'customer_id', 'account_number', 'customer_name',
            'service_address', 'city', 'state', 'zip_code',
            'rate_class', 'service_status'
        ],
        'geo_column': None,
    },
    'meters': {
        'snowflake_table': 'METER_INFRASTRUCTURE',
        'postgres_table': 'meters',
        'primary_key': 'meter_id',
        'columns': [
            'meter_id', 'customer_id', 'transformer_id',
            'meter_type', 'installation_date', 'status'
        ],
        'geo_column': None,
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

def fetch_from_snowflake(table_config: dict, limit: Optional[int] = None) -> pd.DataFrame:
    """Fetch data from Snowflake table."""
    columns = ', '.join(table_config['columns'])
    geo_col = table_config.get('geo_column')
    
    # Convert geometry to WKT for transfer
    if geo_col:
        columns = columns.replace(geo_col, f"ST_ASWKT({geo_col}) as {geo_col}")
    
    query = f"SELECT {columns} FROM {table_config['snowflake_table']}"
    if limit:
        query += f" LIMIT {limit}"
    
    logger.info(f"Fetching from Snowflake: {table_config['snowflake_table']}")
    
    conn = get_snowflake_connection()
    try:
        df = pd.read_sql(query, conn)
        logger.info(f"Fetched {len(df)} rows")
        return df
    finally:
        conn.close()


def create_postgres_table(table_config: dict):
    """Create PostgreSQL table if not exists."""
    table_name = table_config['postgres_table']
    pk = table_config['primary_key']
    geo_col = table_config.get('geo_column')
    
    # Build column definitions (simplified - adjust types as needed)
    col_defs = []
    for col in table_config['columns']:
        if col == pk:
            col_defs.append(f"{col} VARCHAR(100) PRIMARY KEY")
        elif col == geo_col:
            col_defs.append(f"{col} GEOGRAPHY")
        elif 'date' in col.lower():
            col_defs.append(f"{col} DATE")
        elif 'score' in col.lower() or 'rating' in col.lower() or 'mva' in col.lower():
            col_defs.append(f"{col} NUMERIC")
        else:
            col_defs.append(f"{col} VARCHAR(255)")
    
    create_sql = f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
            {', '.join(col_defs)}
        )
    """
    
    conn = get_postgres_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(create_sql)
            
            # Create spatial index if geo column
            if geo_col:
                cur.execute(f"""
                    CREATE INDEX IF NOT EXISTS idx_{table_name}_{geo_col}
                    ON {table_name} USING GIST ({geo_col})
                """)
        conn.commit()
        logger.info(f"Created/verified table: {table_name}")
    finally:
        conn.close()


def sync_to_postgres(table_name: str, df: pd.DataFrame, table_config: dict):
    """Sync DataFrame to PostgreSQL using upsert."""
    pg_table = table_config['postgres_table']
    pk = table_config['primary_key']
    columns = table_config['columns']
    geo_col = table_config.get('geo_column')
    
    conn = get_postgres_connection()
    try:
        with conn.cursor() as cur:
            # Truncate and reload (simple approach)
            cur.execute(f"TRUNCATE TABLE {pg_table}")
            
            # Prepare values
            values = []
            for _, row in df.iterrows():
                row_values = []
                for col in columns:
                    val = row[col.upper()] if col.upper() in row else row.get(col)
                    
                    # Convert WKT to geography
                    if col == geo_col and val:
                        row_values.append(f"ST_GeogFromText('{val}')")
                    else:
                        row_values.append(val)
                values.append(tuple(row_values))
            
            # Build insert SQL
            col_list = ', '.join(columns)
            placeholders = ', '.join(['%s'] * len(columns))
            
            # Handle geometry conversion in SQL
            if geo_col:
                geo_idx = columns.index(geo_col)
                insert_sql = f"""
                    INSERT INTO {pg_table} ({col_list})
                    VALUES %s
                """
                # Use template for geography conversion
                template = '(' + ', '.join([
                    f"ST_GeogFromText(%s)" if i == geo_idx else '%s'
                    for i in range(len(columns))
                ]) + ')'
                execute_values(cur, insert_sql, values, template=template)
            else:
                insert_sql = f"INSERT INTO {pg_table} ({col_list}) VALUES %s"
                execute_values(cur, insert_sql, values)
            
            conn.commit()
            logger.info(f"Synced {len(values)} rows to {pg_table}")
            
    finally:
        conn.close()


def sync_table(table_name: str, limit: Optional[int] = None):
    """Full sync for a single table."""
    if table_name not in SYNC_TABLES:
        logger.error(f"Unknown table: {table_name}")
        return False
    
    config = SYNC_TABLES[table_name]
    
    try:
        # Create table if needed
        create_postgres_table(config)
        
        # Fetch from Snowflake
        df = fetch_from_snowflake(config, limit)
        
        # Sync to PostgreSQL
        sync_to_postgres(table_name, df, config)
        
        return True
    except Exception as e:
        logger.error(f"Error syncing {table_name}: {e}")
        return False


def full_sync(limit: Optional[int] = None):
    """Sync all tables."""
    results = {}
    for table_name in SYNC_TABLES:
        results[table_name] = sync_table(table_name, limit)
    return results


# =============================================================================
# CLI
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description='Sync Snowflake to PostgreSQL')
    parser.add_argument('--tables', type=str, help='Comma-separated table names')
    parser.add_argument('--full-sync', action='store_true', help='Sync all tables')
    parser.add_argument('--limit', type=int, help='Limit rows per table')
    
    args = parser.parse_args()
    
    if args.full_sync:
        results = full_sync(args.limit)
        for table, success in results.items():
            status = '✓' if success else '✗'
            print(f"{status} {table}")
    elif args.tables:
        tables = args.tables.split(',')
        for table in tables:
            success = sync_table(table.strip(), args.limit)
            status = '✓' if success else '✗'
            print(f"{status} {table}")
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
