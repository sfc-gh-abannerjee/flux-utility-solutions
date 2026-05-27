#!/usr/bin/env python3
"""
06b_backfill_pg_substations.py
================================
One-time backfill: populate source_outage_id and substation_id for all
existing rows in public.outages that were inserted by 06_postgres_outage_sync.py
before the format-normalization fix was applied.

Problem solved
--------------
06_postgres_outage_sync.py originally inserted substation_id = NULL for every
row because it used a raw FK-set-lookup with no format normalization:
  - Snowflake TRANSFORMER_METADATA uses 'SUB-HOU-0001' (4-digit) or 'SUB_0021'
    (underscore, 4-digit)
  - PG public.substations uses 'SUB-HOU-001' (3-digit) or 'SUB-0021' (4-digit
    hyphen)
  So the naive lookup found zero matches.

Normalization rules
-------------------
  SUB-HOU-NNNN  →  SUB-HOU-NNN  (drop leading zero, LPAD to 3 digits)
  SUB_NNNN      →  SUB-NNNN     (replace underscore with hyphen, keep 4 digits)

The backfill also sets source_outage_id = the original Snowflake OUTAGE_ID
string (e.g. 'OUT_BERYL_AUG_CENTRAL_1') to enable traceability from PG back
to Snowflake without re-running uuid5.

Matching strategy
-----------------
Uses the deterministic UUID computed in 06_postgres_outage_sync.py:
  uuid5(NAMESPACE_URL, f"flux-outage:{outage_id_str}")
This is exact and unique — avoids float-precision issues with lat/lon or
timezone ambiguity with start_time.

Author : Abhinav Bannerjee
Date   : 2026-05-27
"""

import re
import tomllib
import uuid
from pathlib import Path
from typing import Optional

import psycopg2
import psycopg2.extras
import snowflake.connector

# ---------------------------------------------------------------------------
# Configuration — mirrors 06_postgres_outage_sync.py
# ---------------------------------------------------------------------------

PG_HOST = (
    "<your-pg-host-prefix>"
    ".example.aws.postgres.localhost"
)
PG_HOST_PREFIX = "<your-pg-host-prefix>"
PG_PORT = 5432
PG_DBNAME = "postgres"
PG_USER = "snowflake_admin"

SF_DATABASE = "FLUX_DB"
SF_SCHEMA = "PRODUCTION"
SF_WAREHOUSE = "FLUX_WH"

BATCH_SIZE = 500

# Deterministic UUID namespace — same as 06_postgres_outage_sync.py
_UUID_NS = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")  # uuid.NAMESPACE_URL

# ---------------------------------------------------------------------------
# Snowflake query — fetches (OUTAGE_ID, pg_substation_id) for every outage
# that has a matching transformer with a known SUBSTATION_ID.
# ---------------------------------------------------------------------------

SNOWFLAKE_QUERY = """
SELECT
    o.OUTAGE_ID,
    CASE
        WHEN STARTSWITH(t.SUBSTATION_ID, 'SUB-HOU-')
            THEN 'SUB-HOU-' || LPAD(REGEXP_SUBSTR(t.SUBSTATION_ID, '[0-9]+$')::NUMBER::VARCHAR, 3, '0')
        WHEN STARTSWITH(t.SUBSTATION_ID, 'SUB_')
            THEN 'SUB-' || LPAD(REGEXP_SUBSTR(t.SUBSTATION_ID, '[0-9]+$')::NUMBER::VARCHAR, 4, '0')
        ELSE NULL
    END AS PG_SUBSTATION_ID
FROM FLUX_DB.PRODUCTION.OUTAGE_RESTORATION_TRACKER o
JOIN FLUX_DB.PRODUCTION.TRANSFORMER_METADATA t
    ON t.TRANSFORMER_ID = o.TRANSFORMER_ID
"""

# ---------------------------------------------------------------------------
# Connection helpers — reuse same auth pattern as 06_postgres_outage_sync.py
# ---------------------------------------------------------------------------


def get_snowflake_conn() -> snowflake.connector.SnowflakeConnection:
    """Connect to Snowflake using the 'se_demo' PAT from ~/.snowflake/config.toml."""
    config_path = Path.home() / ".snowflake" / "config.toml"
    with open(config_path, "rb") as f:
        config = tomllib.load(f)

    se = config["connections"]["se_demo"]
    token_path = se.get("token_file_path")
    if not token_path:
        raise RuntimeError("se_demo connection has no token_file_path in config.toml")
    token = Path(token_path).read_text().strip()

    return snowflake.connector.connect(
        account=se["account"],
        user=se["user"],
        authenticator="programmatic_access_token",
        token=token,
        role=se.get("role", "ACCOUNTADMIN"),
        database=SF_DATABASE,
        schema=SF_SCHEMA,
        warehouse=SF_WAREHOUSE,
    )


def get_postgres_conn() -> psycopg2.extensions.connection:
    """Connect to FLUX_OPS_POSTGRES reading the password from ~/.pgpass."""
    pgpass_path = Path.home() / ".pgpass"
    password = None
    for line in pgpass_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if PG_HOST_PREFIX in line:
            parts = line.split(":")
            if len(parts) >= 5:
                password = ":".join(parts[4:])
                break
    if password is None:
        raise RuntimeError(
            f"No .pgpass entry found for host prefix '{PG_HOST_PREFIX}'"
        )
    return psycopg2.connect(
        host=PG_HOST,
        port=PG_PORT,
        dbname=PG_DBNAME,
        user=PG_USER,
        password=password,
        sslmode="require",
    )


# ---------------------------------------------------------------------------
# Normalization helper — also patched into 06_postgres_outage_sync.py
# ---------------------------------------------------------------------------


def normalize_substation_id_for_pg(
    snowflake_id: Optional[str], pg_substation_set: set
) -> Optional[str]:
    """
    Normalize Snowflake TRANSFORMER_METADATA.SUBSTATION_ID to PG format.

    Format mismatch:
      SUB-HOU-0001 (Snowflake, 4-digit) → SUB-HOU-001 (PG, 3-digit)
      SUB_0021     (Snowflake, underscore) → SUB-0021  (PG, hyphen)

    Returns the normalized PG ID if it exists in pg_substation_set, else None.
    Always validates against the live FK set so insertions can never violate
    the outages_substation_id_fkey constraint.
    """
    if not snowflake_id:
        return None

    # SUB-HOU-NNNN → SUB-HOU-NNN  (LPAD 3)
    m = re.match(r"^SUB-HOU-(\d+)$", snowflake_id)
    if m:
        num = int(m.group(1))
        normalized = f"SUB-HOU-{num:03d}"
        return normalized if normalized in pg_substation_set else None

    # SUB_NNNN → SUB-NNNN  (LPAD 4)
    m = re.match(r"^SUB_(\d+)$", snowflake_id)
    if m:
        num = int(m.group(1))
        normalized = f"SUB-{num:04d}"
        return normalized if normalized in pg_substation_set else None

    # Already PG-format?
    if snowflake_id in pg_substation_set:
        return snowflake_id

    return None


def make_outage_uuid(outage_id_str: str) -> str:
    """Deterministic UUID — identical to 06_postgres_outage_sync.py."""
    return str(uuid.uuid5(_UUID_NS, f"flux-outage:{outage_id_str}"))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    print("=" * 60)
    print("06b_backfill_pg_substations.py")
    print("=" * 60)

    # --- Connect ---
    print("\n[1/5] Connecting to Snowflake (se_demo) ...")
    sf_conn = get_snowflake_conn()
    print("      OK")

    print("[2/5] Connecting to Postgres (FLUX_OPS_POSTGRES) ...")
    pg_conn = get_postgres_conn()
    pg_cur = pg_conn.cursor()
    print("      OK")

    # --- Load PG substation FK set ---
    print("[3/5] Loading valid substation IDs from public.substations ...")
    pg_cur.execute("SELECT substation_id FROM public.substations")
    pg_substation_set = {row[0] for row in pg_cur.fetchall()}
    print(f"      {len(pg_substation_set)} substation IDs loaded")

    # --- Fetch Snowflake mapping ---
    print("[4/5] Fetching outage→substation mapping from Snowflake ...")
    sf_cur = sf_conn.cursor()
    sf_cur.execute(SNOWFLAKE_QUERY)
    sf_rows = sf_cur.fetchall()
    sf_cur.close()
    sf_conn.close()
    print(f"      {len(sf_rows)} rows fetched from Snowflake")

    # --- Build update batch ---
    print("[5/5] Updating public.outages (source_outage_id + substation_id) ...")
    updates: list = []
    null_substation_count = 0
    unmapped_snowflake_ids: list = []

    for outage_id_str, pg_sub_id_raw in sf_rows:
        pg_uuid = make_outage_uuid(outage_id_str)
        validated_sub_id = normalize_substation_id_for_pg(pg_sub_id_raw, pg_substation_set)

        if pg_sub_id_raw and not validated_sub_id:
            null_substation_count += 1
            unmapped_snowflake_ids.append(pg_sub_id_raw)
        elif not pg_sub_id_raw:
            null_substation_count += 1

        # (source_outage_id, substation_id, outage_id)
        updates.append((outage_id_str, validated_sub_id, pg_uuid))

    # --- Execute UPDATEs in batches ---
    UPDATE_SQL = """
        UPDATE public.outages
        SET source_outage_id = data.source_id,
            substation_id    = data.sub_id
        FROM (VALUES %s) AS data(source_id, sub_id, pg_uuid)
        WHERE outage_id = data.pg_uuid::uuid
    """
    rows_updated_total = 0
    for i in range(0, len(updates), BATCH_SIZE):
        batch = updates[i : i + BATCH_SIZE]
        pg_cur.execute("BEGIN")
        psycopg2.extras.execute_values(pg_cur, UPDATE_SQL, batch)
        affected = pg_cur.rowcount
        pg_conn.commit()
        rows_updated_total += affected
        print(f"      Batch {i // BATCH_SIZE + 1}: {affected} rows updated")

    # --- Final verification ---
    pg_cur.execute(
        "SELECT COUNT(*) AS total, COUNT(substation_id) AS with_sub, "
        "COUNT(source_outage_id) AS with_src FROM public.outages"
    )
    total, with_sub, with_src = pg_cur.fetchone()
    coverage_pct = (with_sub / total * 100) if total else 0

    pg_cur.close()
    pg_conn.close()

    # --- Summary ---
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"  Snowflake outages fetched:           {len(sf_rows)}")
    print(f"  PG rows updated:                     {rows_updated_total}")
    print(f"  Final public.outages total:          {total}")
    print(f"  Rows with substation_id:             {with_sub}")
    print(f"  Rows with source_outage_id:          {with_src}")
    print(f"  Substation coverage:                 {coverage_pct:.1f}%")
    print(f"  Unmapped substation IDs (NULL set):  {null_substation_count}")
    if unmapped_snowflake_ids:
        sample = list(set(unmapped_snowflake_ids))[:5]
        print(f"  Sample unmapped IDs: {sample}")
    print("=" * 60)


if __name__ == "__main__":
    main()
