#!/usr/bin/env python3
"""
Flux Utility Solutions - Validation Tool
=========================================
Validate deployment matches expected state.

Usage:
    python validate.py --env prod
    python validate.py --env dev --check tables
    python validate.py --env staging --check all
"""

import argparse
import subprocess
import sys
import yaml
from pathlib import Path
from typing import Dict, List

SCRIPT_DIR = Path(__file__).parent.parent / "scripts"
CONFIG_FILE = SCRIPT_DIR / "config.yaml"


def load_config(env: str) -> Dict:
    """Load configuration for the specified environment."""
    with open(CONFIG_FILE, 'r') as f:
        config = yaml.safe_load(f)
    return config.get(env, {})


def run_sql(sql: str, connection: str = "default") -> str:
    """Execute SQL and return output."""
    cmd = ["snow", "sql", "-q", sql, "-c", connection, "-o", "json"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else result.stderr


def check_tables(config: Dict, connection: str) -> List[Dict]:
    """Check that all required tables exist."""
    database = config.get("database", "FLUX_DATABASE")
    
    expected_tables = [
        "SUBSTATIONS",
        "TRANSFORMER_METADATA", 
        "CIRCUIT_METADATA",
        "GRID_POLES_INFRASTRUCTURE",
        "METER_INFRASTRUCTURE",
        "METER_BUILDING_MATCHES",
        "CUSTOMERS_MASTER_DATA",
        "CUSTOMER_SEGMENT_CONFIG",
        "AMI_INTERVAL_READINGS",
        "AMI_READINGS_FINAL",
        "TRANSFORMER_HOURLY_LOAD",
        "TRANSFORMER_THERMAL_STRESS_MATERIALIZED",
    ]
    
    results = []
    sql = f"SHOW TABLES IN {database}.PRODUCTION"
    output = run_sql(sql, connection)
    
    for table in expected_tables:
        exists = table.lower() in output.lower()
        results.append({
            "check": f"Table {table}",
            "status": "PASS" if exists else "FAIL",
            "message": "Exists" if exists else "Not found"
        })
    
    return results


def check_semantic_views(config: Dict, connection: str) -> List[Dict]:
    """Check semantic views exist."""
    database = config.get("database", "FLUX_DATABASE")
    
    results = []
    sql = f"SHOW SEMANTIC VIEWS IN {database}.APPLICATIONS"
    output = run_sql(sql, connection)
    
    expected = ["UTILITY_SEMANTIC_VIEW"]
    for view in expected:
        exists = view.lower() in output.lower()
        results.append({
            "check": f"Semantic View {view}",
            "status": "PASS" if exists else "FAIL",
            "message": "Exists" if exists else "Not found"
        })
    
    return results


def check_search_services(config: Dict, connection: str) -> List[Dict]:
    """Check Cortex Search services exist."""
    database = config.get("database", "FLUX_DATABASE")
    
    results = []
    sql = f"SHOW CORTEX SEARCH SERVICES IN {database}.APPLICATIONS"
    output = run_sql(sql, connection)
    
    expected = [
        "CUSTOMER_SEARCH_SERVICE",
        "AMI_METADATA_SEARCH",
        "TECHNICAL_MANUALS_SEARCH_SERVICE"
    ]
    
    for service in expected:
        exists = service.lower() in output.lower()
        results.append({
            "check": f"Search Service {service}",
            "status": "PASS" if exists else "FAIL",
            "message": "Exists" if exists else "Not found"
        })
    
    return results


def check_agents(config: Dict, connection: str) -> List[Dict]:
    """Check Cortex Agents exist."""
    database = config.get("database", "FLUX_DATABASE")
    
    results = []
    sql = f"SHOW AGENTS IN {database}.APPLICATIONS"
    output = run_sql(sql, connection)
    
    expected = ["GRID_INTELLIGENCE_AGENT"]
    for agent in expected:
        exists = agent.lower() in output.lower()
        results.append({
            "check": f"Agent {agent}",
            "status": "PASS" if exists else "FAIL",
            "message": "Exists" if exists else "Not found"
        })
    
    return results


def check_row_counts(config: Dict, connection: str) -> List[Dict]:
    """Check key tables have expected row counts."""
    database = config.get("database", "FLUX_DATABASE")
    
    expectations = [
        ("TRANSFORMER_METADATA", 90000, 92000),
        ("CUSTOMERS_MASTER_DATA", 680000, 690000),
        ("METER_INFRASTRUCTURE", 590000, 600000),
        ("SUBSTATIONS", 95, 100),
    ]
    
    results = []
    for table, min_rows, max_rows in expectations:
        sql = f"SELECT COUNT(*) as CNT FROM {database}.PRODUCTION.{table}"
        output = run_sql(sql, connection)
        
        try:
            # Parse count from JSON output
            import json
            data = json.loads(output)
            count = int(data[0]["CNT"]) if data else 0
            
            in_range = min_rows <= count <= max_rows
            results.append({
                "check": f"Row count {table}",
                "status": "PASS" if in_range else "WARN",
                "message": f"{count:,} rows (expected {min_rows:,}-{max_rows:,})"
            })
        except:
            results.append({
                "check": f"Row count {table}",
                "status": "ERROR",
                "message": "Could not get count"
            })
    
    return results


def validate(env: str, checks: List[str], connection: str) -> None:
    """Run validation checks."""
    config = load_config(env)
    
    print(f"\n{'='*60}")
    print(f"FLUX DEPLOYMENT VALIDATION")
    print(f"Environment: {env}")
    print(f"Database: {config.get('database', 'N/A')}")
    print(f"{'='*60}\n")
    
    all_results = []
    
    if "tables" in checks or "all" in checks:
        print("Checking tables...")
        all_results.extend(check_tables(config, connection))
    
    if "semantic" in checks or "all" in checks:
        print("Checking semantic views...")
        all_results.extend(check_semantic_views(config, connection))
    
    if "search" in checks or "all" in checks:
        print("Checking search services...")
        all_results.extend(check_search_services(config, connection))
    
    if "agents" in checks or "all" in checks:
        print("Checking agents...")
        all_results.extend(check_agents(config, connection))
    
    if "counts" in checks or "all" in checks:
        print("Checking row counts...")
        all_results.extend(check_row_counts(config, connection))
    
    # Print results
    print(f"\n{'='*60}")
    print("VALIDATION RESULTS")
    print(f"{'='*60}\n")
    
    pass_count = 0
    fail_count = 0
    
    for result in all_results:
        icon = "✅" if result["status"] == "PASS" else "❌" if result["status"] == "FAIL" else "⚠️"
        print(f"{icon} {result['check']}: {result['status']}")
        print(f"   {result['message']}")
        
        if result["status"] == "PASS":
            pass_count += 1
        elif result["status"] == "FAIL":
            fail_count += 1
    
    print(f"\n{'='*60}")
    print(f"SUMMARY: {pass_count} passed, {fail_count} failed")
    print(f"{'='*60}")
    
    sys.exit(0 if fail_count == 0 else 1)


def main():
    parser = argparse.ArgumentParser(
        description="Flux Utility Solutions Validation Tool"
    )
    
    parser.add_argument(
        "--env", "-e",
        choices=["dev", "staging", "prod", "si_demos"],
        default="si_demos",
        help="Target environment"
    )
    
    parser.add_argument(
        "--check", "-c",
        nargs="+",
        choices=["all", "tables", "semantic", "search", "agents", "counts"],
        default=["all"],
        help="Checks to run"
    )
    
    parser.add_argument(
        "--connection",
        default="default",
        help="Snow CLI connection name"
    )
    
    args = parser.parse_args()
    validate(args.env, args.check, args.connection)


if __name__ == "__main__":
    main()
