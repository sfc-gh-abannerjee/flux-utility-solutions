"""
Flux Utility Solutions - Seed Data Loader
Loads generated parquet files into Snowflake tables.
"""

import snowflake.connector
from snowflake.connector.pandas_tools import write_pandas
import pandas as pd
import argparse
import os
import json
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)


def get_snowflake_connection(connection_name: str = None):
    """Get Snowflake connection using snowflake-connector-python"""
    
    # Try to use connection from toml config
    try:
        import toml
        config_path = os.path.expanduser("~/.snowflake/connections.toml")
        
        if os.path.exists(config_path):
            config = toml.load(config_path)
            conn_config = config.get(connection_name or 'default', {})
            
            return snowflake.connector.connect(
                account=conn_config.get('account'),
                user=conn_config.get('user'),
                password=conn_config.get('password'),
                authenticator=conn_config.get('authenticator', 'snowflake'),
                warehouse=conn_config.get('warehouse'),
                database=conn_config.get('database'),
                schema=conn_config.get('schema'),
                role=conn_config.get('role')
            )
    except Exception as e:
        print(f"Warning: Could not load from config: {e}")
    
    # Fall back to environment variables
    return snowflake.connector.connect(
        account=os.environ.get('SNOWFLAKE_ACCOUNT'),
        user=os.environ.get('SNOWFLAKE_USER'),
        password=os.environ.get('SNOWFLAKE_PASSWORD'),
        warehouse=os.environ.get('SNOWFLAKE_WAREHOUSE', 'FLUX_DEV_MEDIUM'),
        database=os.environ.get('SNOWFLAKE_DATABASE', 'FLUX_DEV'),
        schema=os.environ.get('SNOWFLAKE_SCHEMA', 'PRODUCTION'),
        role=os.environ.get('SNOWFLAKE_ROLE', 'ACCOUNTADMIN')
    )


def load_parquet_to_table(
    conn,
    parquet_path: str,
    table_name: str,
    database: str,
    schema: str,
    truncate: bool = False
):
    """Load a parquet file into a Snowflake table"""
    
    if not os.path.exists(parquet_path):
        print(f"  ⚠ File not found: {parquet_path}")
        return 0
    
    print(f"  Loading {parquet_path} → {database}.{schema}.{table_name}")
    
    # Read parquet
    df = pd.read_parquet(parquet_path)
    
    # Truncate if requested
    if truncate:
        cursor = conn.cursor()
        cursor.execute(f"TRUNCATE TABLE IF EXISTS {database}.{schema}.{table_name}")
        cursor.close()
    
    # Write to Snowflake
    success, nchunks, nrows, _ = write_pandas(
        conn,
        df,
        table_name,
        database=database,
        schema=schema,
        auto_create_table=False,
        overwrite=truncate
    )
    
    if success:
        print(f"    ✓ Loaded {nrows:,} rows")
    else:
        print(f"    ✗ Failed to load")
    
    return nrows


def load_seed_data(
    source: str = 'small',
    database: str = 'FLUX_DEV',
    schema: str = 'PRODUCTION',
    connection_name: str = None,
    quick: bool = False
):
    """Load all seed data files"""
    
    seed_dir = os.path.join(REPO_ROOT, 'seed_data', source)
    
    # Check for manifest
    manifest_path = os.path.join(seed_dir, 'manifest.json')
    
    if os.path.exists(manifest_path):
        with open(manifest_path) as f:
            manifest = json.load(f)
        files = manifest.get('files', [])
    else:
        # Default file mapping
        files = [
            {'file': 'substations.parquet', 'table': 'SUBSTATIONS'},
            {'file': 'transformers.parquet', 'table': 'TRANSFORMER_METADATA'},
            {'file': 'customers.parquet', 'table': 'CUSTOMERS_MASTER_DATA'},
        ]
        
        if not quick:
            files.append({'file': 'ami_readings.parquet', 'table': 'AMI_INTERVAL_READINGS'})
    
    print(f"\n{'='*60}")
    print(f"Flux Utility Solutions - Seed Data Loader")
    print(f"{'='*60}")
    print(f"Source: {source}")
    print(f"Target: {database}.{schema}")
    print(f"Files: {len(files)}")
    print(f"{'='*60}\n")
    
    conn = get_snowflake_connection(connection_name)
    
    total_rows = 0
    
    for file_config in files:
        file_path = os.path.join(seed_dir, file_config['file'])
        table_name = file_config['table']
        
        try:
            rows = load_parquet_to_table(
                conn,
                file_path,
                table_name,
                database,
                schema,
                truncate=file_config.get('truncate', True)
            )
            total_rows += rows
        except Exception as e:
            print(f"    ✗ Error: {e}")
    
    conn.close()
    
    print(f"\n{'='*60}")
    print(f"✓ Seed data loading complete")
    print(f"  Total rows loaded: {total_rows:,}")
    print(f"{'='*60}\n")


def main():
    parser = argparse.ArgumentParser(description='Load seed data to Snowflake')
    parser.add_argument('--source', choices=['small', 'full'], default='small',
                       help='Seed data source directory')
    parser.add_argument('--database', type=str, default='FLUX_DEV',
                       help='Target database')
    parser.add_argument('--schema', type=str, default='PRODUCTION',
                       help='Target schema')
    parser.add_argument('--connection', type=str, help='Snowflake connection name')
    parser.add_argument('--quick', action='store_true',
                       help='Skip large AMI table for quick loading')
    
    args = parser.parse_args()
    
    load_seed_data(
        source=args.source,
        database=args.database,
        schema=args.schema,
        connection_name=args.connection,
        quick=args.quick
    )


if __name__ == '__main__':
    main()
