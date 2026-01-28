"""
Flux Utility Solutions - Generate All Data
Master script to generate complete seed data.
"""

import subprocess
import sys
import os
import argparse
import json
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def run_generator(script: str, args: list = None):
    """Run a generator script"""
    cmd = [sys.executable, os.path.join(SCRIPT_DIR, script)]
    if args:
        cmd.extend(args)
    
    print(f"\n{'─'*60}")
    print(f"Running: {script}")
    print(f"{'─'*60}")
    
    result = subprocess.run(cmd, capture_output=False)
    return result.returncode == 0


def create_manifest(output_dir: str, files: list):
    """Create manifest.json for the seed data"""
    manifest = {
        'generated_at': datetime.now().isoformat(),
        'generator_version': '1.0.0',
        'files': files
    }
    
    manifest_path = os.path.join(output_dir, 'manifest.json')
    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)
    
    print(f"\n✓ Created {manifest_path}")


def main():
    parser = argparse.ArgumentParser(description='Generate all seed data')
    parser.add_argument('--output', type=str, default='../seed_data/small',
                       help='Output directory')
    parser.add_argument('--size', choices=['small', 'full'], default='small',
                       help='Data size: small (quick demo) or full (production scale)')
    
    args = parser.parse_args()
    
    # Size configurations
    if args.size == 'small':
        config = {
            'substations': 98,
            'transformers': 5000,
            'customers': 25000,
            'ami_days': 7,
            'ami_meters': 1000
        }
    else:  # full
        config = {
            'substations': 98,
            'transformers': 91000,
            'customers': 686000,
            'ami_days': 30,
            'ami_meters': 10000
        }
    
    output_dir = os.path.abspath(os.path.join(SCRIPT_DIR, args.output))
    os.makedirs(output_dir, exist_ok=True)
    
    print(f"\n{'='*60}")
    print(f"Flux Utility Solutions - Data Generator")
    print(f"{'='*60}")
    print(f"Size: {args.size}")
    print(f"Output: {output_dir}")
    print(f"Config: {config}")
    print(f"{'='*60}")
    
    files = []
    
    # Generate substations
    sub_file = os.path.join(output_dir, 'substations.parquet')
    if run_generator('generate_substations.py', [
        '--count', str(config['substations']),
        '--output', sub_file
    ]):
        files.append({'file': 'substations.parquet', 'table': 'SUBSTATIONS', 'truncate': True})
    
    # Generate transformers
    trans_file = os.path.join(output_dir, 'transformers.parquet')
    if run_generator('generate_transformers.py', [
        '--count', str(config['transformers']),
        '--output', trans_file,
        '--substations', sub_file
    ]):
        files.append({'file': 'transformers.parquet', 'table': 'TRANSFORMER_METADATA', 'truncate': True})
    
    # Generate customers
    cust_file = os.path.join(output_dir, 'customers.parquet')
    if run_generator('generate_customers.py', [
        '--count', str(config['customers']),
        '--output', cust_file
    ]):
        files.append({'file': 'customers.parquet', 'table': 'CUSTOMERS_MASTER_DATA', 'truncate': True})
    
    # Generate AMI readings
    ami_file = os.path.join(output_dir, 'ami_readings.parquet')
    if run_generator('generate_ami_sample.py', [
        '--meters', str(config['ami_meters']),
        '--days', str(config['ami_days']),
        '--output', ami_file,
        '--customers', cust_file
    ]):
        files.append({'file': 'ami_readings.parquet', 'table': 'AMI_INTERVAL_READINGS', 'truncate': False})
    
    # Create manifest
    create_manifest(output_dir, files)
    
    print(f"\n{'='*60}")
    print(f"✓ Data generation complete!")
    print(f"  Files: {len(files)}")
    print(f"  Output: {output_dir}")
    print(f"\nNext: Load to Snowflake with:")
    print(f"  python generators/load_seed_data.py --source {args.size}")
    print(f"{'='*60}\n")


if __name__ == '__main__':
    main()
