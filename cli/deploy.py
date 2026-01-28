#!/usr/bin/env python3
"""
Flux Utility Solutions - CLI Deployment Tool
=============================================
Automated deployment of Flux solution using Snow CLI.

Usage:
    python deploy.py --env dev --dry-run
    python deploy.py --env prod --scripts 01,02,03
    python deploy.py --env staging --all
"""

import argparse
import os
import subprocess
import sys
import yaml
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict

# Configuration
SCRIPT_DIR = Path(__file__).parent.parent / "scripts"
CONFIG_FILE = SCRIPT_DIR / "config.yaml"

# Script execution order
SCRIPT_ORDER = [
    "01_database_infrastructure.sql",
    "02_warehouses.sql",
    "03_substations_transformers.sql",
    "04_meters_infrastructure.sql",
    "05_customers_master.sql",
    "06_ami_readings_pipeline.sql",
    "07_aggregation_tables.sql",
    "08_semantic_view.sql",
    "09_cortex_search_services.sql",
    "10_cortex_agent.sql",
    "11_ml_feature_tables.sql",
    "12_postgres_instance.sql",
    "13_spcs_compute.sql",
    "14_geospatial_functions.sql",
    "15_marketplace_listings.sql",
    "16_rbac_final.sql",
    "17_validation_queries.sql",
    "18_deploy_orchestrator.sql",
    "19_git_integration.sql",
]


def load_config(env: str) -> Dict:
    """Load configuration for the specified environment."""
    with open(CONFIG_FILE, 'r') as f:
        config = yaml.safe_load(f)
    
    if env not in config:
        print(f"Error: Environment '{env}' not found in config.yaml")
        print(f"Available environments: {list(config.keys())}")
        sys.exit(1)
    
    return config[env]


def render_template(sql_content: str, config: Dict) -> str:
    """Render Jinja2 template with configuration values."""
    for key, value in config.items():
        sql_content = sql_content.replace(f"{{{{ {key} }}}}", str(value))
    return sql_content


def execute_sql(sql_file: Path, config: Dict, dry_run: bool = False, 
                connection: str = "default") -> bool:
    """Execute a SQL file using Snow CLI."""
    
    # Read and render template
    with open(sql_file, 'r') as f:
        sql_content = f.read()
    
    rendered_sql = render_template(sql_content, config)
    
    if dry_run:
        print(f"\n{'='*60}")
        print(f"DRY RUN: {sql_file.name}")
        print(f"{'='*60}")
        print(f"Would execute with config:")
        for key, value in config.items():
            print(f"  {key}: {value}")
        print(f"SQL preview (first 500 chars):")
        print(rendered_sql[:500])
        return True
    
    # Write rendered SQL to temp file
    temp_file = Path(f"/tmp/flux_deploy_{sql_file.stem}.sql")
    with open(temp_file, 'w') as f:
        f.write(rendered_sql)
    
    # Execute via Snow CLI
    try:
        cmd = [
            "snow", "sql",
            "-f", str(temp_file),
            "-c", connection
        ]
        
        print(f"\nExecuting: {sql_file.name}")
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600  # 10 minute timeout
        )
        
        if result.returncode == 0:
            print(f"✅ SUCCESS: {sql_file.name}")
            if result.stdout:
                print(result.stdout[:1000])
            return True
        else:
            print(f"❌ FAILED: {sql_file.name}")
            print(f"Error: {result.stderr}")
            return False
            
    except subprocess.TimeoutExpired:
        print(f"⏱️ TIMEOUT: {sql_file.name}")
        return False
    except FileNotFoundError:
        print("Error: Snow CLI not found. Install with: pip install snowflake-cli")
        sys.exit(1)
    finally:
        # Cleanup temp file
        if temp_file.exists():
            temp_file.unlink()


def deploy(env: str, scripts: Optional[List[str]] = None, 
           dry_run: bool = False, connection: str = "default") -> None:
    """Deploy Flux solution to specified environment."""
    
    print(f"\n{'#'*60}")
    print(f"# FLUX UTILITY SOLUTIONS DEPLOYMENT")
    print(f"# Environment: {env}")
    print(f"# Timestamp: {datetime.now().isoformat()}")
    print(f"# Dry Run: {dry_run}")
    print(f"{'#'*60}\n")
    
    # Load configuration
    config = load_config(env)
    print(f"Configuration loaded for '{env}':")
    for key, value in config.items():
        print(f"  {key}: {value}")
    
    # Determine which scripts to run
    if scripts:
        # Parse script numbers (e.g., "01,02,03" or "01-05")
        script_nums = set()
        for item in scripts:
            if '-' in item:
                start, end = item.split('-')
                script_nums.update(range(int(start), int(end) + 1))
            else:
                script_nums.add(int(item))
        
        scripts_to_run = [
            s for s in SCRIPT_ORDER 
            if int(s.split('_')[0]) in script_nums
        ]
    else:
        scripts_to_run = SCRIPT_ORDER
    
    print(f"\nScripts to execute: {len(scripts_to_run)}")
    for script in scripts_to_run:
        print(f"  - {script}")
    
    # Execute scripts
    results = []
    for script in scripts_to_run:
        script_path = SCRIPT_DIR / script
        if not script_path.exists():
            print(f"⚠️ Script not found: {script}")
            results.append((script, "NOT_FOUND"))
            continue
        
        success = execute_sql(script_path, config, dry_run, connection)
        results.append((script, "SUCCESS" if success else "FAILED"))
        
        if not success and not dry_run:
            print("\n⚠️ Deployment stopped due to error.")
            break
    
    # Summary
    print(f"\n{'='*60}")
    print("DEPLOYMENT SUMMARY")
    print(f"{'='*60}")
    
    for script, status in results:
        icon = "✅" if status == "SUCCESS" else "❌" if status == "FAILED" else "⚠️"
        print(f"{icon} {script}: {status}")
    
    success_count = sum(1 for _, s in results if s == "SUCCESS")
    print(f"\nTotal: {success_count}/{len(results)} successful")


def main():
    parser = argparse.ArgumentParser(
        description="Flux Utility Solutions CLI Deployment Tool"
    )
    
    parser.add_argument(
        "--env", "-e",
        choices=["dev", "staging", "prod", "si_demos"],
        default="dev",
        help="Target environment (default: dev)"
    )
    
    parser.add_argument(
        "--scripts", "-s",
        type=lambda x: x.split(','),
        help="Specific scripts to run (e.g., '01,02,03' or '01-05')"
    )
    
    parser.add_argument(
        "--all", "-a",
        action="store_true",
        help="Run all scripts"
    )
    
    parser.add_argument(
        "--dry-run", "-d",
        action="store_true",
        help="Show what would be executed without running"
    )
    
    parser.add_argument(
        "--connection", "-c",
        default="default",
        help="Snow CLI connection name (default: default)"
    )
    
    args = parser.parse_args()
    
    # Validate
    if not args.scripts and not args.all:
        print("Please specify --scripts or --all")
        parser.print_help()
        sys.exit(1)
    
    # Deploy
    deploy(
        env=args.env,
        scripts=args.scripts,
        dry_run=args.dry_run,
        connection=args.connection
    )


if __name__ == "__main__":
    main()
