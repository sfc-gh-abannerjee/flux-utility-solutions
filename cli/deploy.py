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

# Script execution order.
#
# 2026-07-29: this list stopped at 19_git_integration.sql, so 22 of the 41 scripts in
# scripts/ were NEVER deployed -- including 30_ops_center_dependencies.sql, which builds
# every view the SPCS Ops Center queries, 31_regenerate_coherent_topology.sql, which
# produces the correct grid topology, and 99_validate_deployment.sql. A new user ran
# deploy.py, got a partial database, and the dashboard had no views. All 41 are listed
# now; keep this in sync when adding a script (validated by scripts_in_order_match_disk
# in cli/validate.py).
# Ordering notes that are NOT just numeric. These were found by actually running a
# fresh deploy into a scratch database on 2026-07-29, not by reading the scripts:
#   - 31 (regenerate topology) must run BEFORE 30, because 30 derives its
#     PRECOMPUTED_CASCADES patient-zero from PRODUCTION.SUBSTATIONS and its views read
#     the regenerated tables.
#   - 30 must run BEFORE 08, because 30 is the ONLY script that creates
#     PRODUCTION.OUTAGE_RESTORATION_TRACKER, and 08's semantic view selects from it.
#     Deploying in numeric order fails with "Table OUTAGE_RESTORATION_TRACKER does not
#     exist". Verified safe: 30 has no reference to the semantic view or to any Cortex
#     Search service, so moving it earlier creates no new cycle.
#   - 32 (invariants) must run AFTER 30 and 31, since it asserts the post-regeneration
#     state, and 99 (validation) runs last.
#   - 19 (git integration) must run BEFORE 51_load_seed_data.sql, which COPY INTOs from
#     '@FLUX_SOLUTIONS_REPO/branches/main/seed_data/parquet'. That stage does not exist
#     until 19 creates the GIT REPOSITORY and FETCHes it.
#   - 53/53a/55/55a (PDF stages + doc tools) must run BEFORE 10, because the agent spec
#     in 10 wires tools to APPLICATIONS.PARSE_AND_EXTRACT, a procedure created by 55.
#     Numeric order put them last, so a fresh deploy failed with
#     "Procedure 'APPLICATIONS.PARSE_AND_EXTRACT' does not exist".
SCRIPT_ORDER = [
    # --- core infrastructure and base tables ---
    "01_database_infrastructure.sql",
    "02_warehouses.sql",
    "03_substations_transformers.sql",
    "04_meters_infrastructure.sql",
    "05_customers_master.sql",
    "06_ami_readings_pipeline.sql",
    "07_aggregation_tables.sql",
    # --- git integration, required by the parquet seed loaders below ---
    "19_git_integration.sql",
    # --- seed data, before the regeneration that re-parents it ---
    "50_load_seed_data.sql",
    "51_load_seed_data.sql",
    "51_load_full_seed_data.sql",
    "51_generate_ami_sample.sql",
    "52_load_ami_from_s3.sql",
    "60_ami_chunked_orchestration.sql",
    # --- topology regeneration, then the tables/views that read it ---
    "31_regenerate_coherent_topology.sql",
    "30_ops_center_dependencies.sql",
    # --- document/PDF tooling: creates PARSE_AND_EXTRACT, needed by the agent in 10 ---
    "53_utility_pdf_stage.sql",
    "53a_internal_stage_validate.sql",
    "55_pdf_doc_tools.sql",
    "55a_pdf_doc_tools_validate.sql",
    # --- semantic + AI layer (needs OUTAGE_RESTORATION_TRACKER from 30) ---
    "08_semantic_view.sql",
    "09_cortex_search_services.sql",
    "10_cortex_agent.sql",
    "11_ml_feature_tables.sql",
    # --- infrastructure, access and apps ---
    "12_postgres_instance.sql",
    "13_spcs_compute.sql",
    "14_geospatial_functions.sql",
    "15_marketplace_listings.sql",
    "16_rbac_final.sql",
    "17_validation_queries.sql",
    "18_deploy_orchestrator.sql",
    "20_model_registry.sql",
    "21_cascade_procedures.sql",
    "22_sample_queries.sql",
    "23_postgres_external_access.sql",
    "24_postgres_sync_pipeline.sql",
    "24_streamlit_stage_setup.sql",
    "25_streamlit_apps.sql",
    "26_notebooks_deployment.sql",
    # --- assertions, then final validation ---
    "32_topology_invariants.sql",
    "99_validate_deployment.sql",
]


def load_config(env: str) -> Dict:
    """
    Load configuration for the specified environment.

    2026-07-29: the 'common:' block in config.yaml was never merged in, so shared keys
    were invisible to templating. It is now merged under the environment, with the
    environment's own keys winning on conflict.

    postgres_password is deliberately NOT read from config.yaml -- a deployment
    credential does not belong in a file that gets committed. It comes from the
    FLUX_POSTGRES_PASSWORD environment variable, and is only required by the one
    script that uses it (23_postgres_external_access.sql).
    """
    with open(CONFIG_FILE, 'r') as f:
        config = yaml.safe_load(f)

    if env not in config:
        print(f"Error: Environment '{env}' not found in config.yaml")
        print(f"Available environments: {[k for k in config if k != 'common']}")
        sys.exit(1)

    merged = dict(config.get("common", {}))
    merged.update(config[env])
    merged.setdefault("environment", env)

    pg_pw = os.environ.get("FLUX_POSTGRES_PASSWORD")
    if pg_pw:
        merged["postgres_password"] = pg_pw

    return merged


def render_template(sql_content: str, config: Dict) -> str:
    """
    Substitute config values into a SQL script.

    2026-07-29: this only handled the "{{ key }}" form, but 36 of the 41 scripts in
    scripts/ use the "<% key %>" form and none use "{{ key }}". So no script was ever
    actually rendered -- a deploy sent the literal placeholder to Snowflake and failed
    on the first templated statement. Both forms are now supported, with and without
    inner padding, so either convention works.
    """
    for key, value in config.items():
        for pattern in (f"<% {key} %>", f"<%{key}%>",
                        f"{{{{ {key} }}}}", f"{{{{{key}}}}}"):
            sql_content = sql_content.replace(pattern, str(value))
    return sql_content


def unrendered_placeholders(sql_content: str) -> list:
    """
    Return any placeholders left after rendering.

    A leftover placeholder means config.yaml is missing a key the script needs.
    Failing loudly here is much cheaper than a confusing Snowflake syntax error.
    """
    import re
    return sorted(set(
        re.findall(r"<%\s*[A-Za-z_][A-Za-z0-9_]*\s*%>", sql_content) +
        re.findall(r"\{\{\s*[A-Za-z_][A-Za-z0-9_]*\s*\}\}", sql_content)
    ))


def execute_sql(sql_file: Path, config: Dict, dry_run: bool = False, 
                connection: str = "default") -> bool:
    """Execute a SQL file using Snow CLI."""
    
    # Read and render template
    with open(sql_file, 'r') as f:
        sql_content = f.read()
    
    rendered_sql = render_template(sql_content, config)

    # Fail before touching Snowflake if any placeholder is still unresolved. Sending a
    # literal "<% database %>" produces a confusing SQL syntax error several statements
    # in; naming the missing config key here is far cheaper to diagnose.
    leftover = unrendered_placeholders(rendered_sql)
    if leftover:
        print(f"\n  ERROR {sql_file.name}: unresolved placeholder(s): {', '.join(leftover)}")
        missing = [p.strip("<%>{} ") for p in leftover]
        print(f"        add to scripts/config.yaml (or export FLUX_POSTGRES_PASSWORD): {', '.join(missing)}")
        return False

    if dry_run:
        print(f"\n{'='*60}")
        print(f"DRY RUN: {sql_file.name}")
        print(f"{'='*60}")
        print(f"Would execute with config:")
        for key, value in config.items():
            shown = "***" if "password" in key.lower() else value
            print(f"  {key}: {shown}")
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
        shown = "***" if "password" in key.lower() else value
        print(f"  {key}: {shown}")

    # Determine which scripts to run.
    #
    # 2026-07-29: this did int(item) on each --scripts token and int(s.split('_')[0]) on
    # each candidate, so it crashed two ways: passing a filename raised ValueError, and
    # any range covering 53a/55a raised on int('53a'). Selection now accepts filenames,
    # bare prefixes and ranges, and compares on the numeric part so letter-suffixed
    # scripts match. Output always follows SCRIPT_ORDER, never the order given.
    if scripts:
        wanted_files, wanted_prefixes = set(), set()
        for raw in scripts:
            item = raw.strip()
            if not item:
                continue
            if item.endswith(".sql"):
                wanted_files.add(item)
            elif "-" in item and all(part.strip().isdigit() for part in item.split("-", 1)):
                start, end = (int(part) for part in item.split("-", 1))
                wanted_prefixes.update(str(n).zfill(2) for n in range(start, end + 1))
            else:
                wanted_prefixes.add(item.zfill(2) if item.isdigit() else item)

        def _matches(name: str) -> bool:
            if name in wanted_files:
                return True
            prefix = name.split("_")[0]                      # e.g. "53a"
            numeric = "".join(ch for ch in prefix if ch.isdigit())
            return prefix in wanted_prefixes or numeric in wanted_prefixes

        scripts_to_run = [s for s in SCRIPT_ORDER if _matches(s)]

        unknown = wanted_files - set(SCRIPT_ORDER)
        if unknown:
            print(f"\n⚠️  Not in SCRIPT_ORDER, will be skipped: {', '.join(sorted(unknown))}")
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
    
    # 2026-07-29: these choices were hardcoded to ["dev","staging","prod","si_demos"].
    # "si_demos" was the database on the cpe_demo_CLI account, deleted 2026-05-23, so it
    # was an unusable option; meanwhile "local" existed in config.yaml but could not be
    # selected. Read the environments from config.yaml so the two can never drift again.
    try:
        with open(CONFIG_FILE) as _f:
            _envs = [k for k in yaml.safe_load(_f) if k != "common"]
    except Exception:
        _envs = ["dev", "staging", "prod"]

    parser.add_argument(
        "--env", "-e",
        choices=_envs,
        default="dev" if "dev" in _envs else _envs[0],
        help=f"Target environment (default: dev). From config.yaml: {', '.join(_envs)}"
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
