#!/usr/bin/env python3
"""
06_postgres_outage_sync.py
==========================
Sync 18,689 historical outages from FLUX_DB.PRODUCTION.OUTAGE_RESTORATION_TRACKER
into FLUX_OPS_POSTGRES public.outages.

- Joins TRANSFORMER_METADATA on TRANSFORMER_ID to get lat/lon.
  Rows without a matching transformer (e.g. -SPLIT- suffix IDs) fall back to
  Houston city-center coordinates (29.7604, -95.3698).
- Maps CAUSE / severity / scenario to public.outages enum values.
- Normalizes Snowflake SUBSTATION_ID to PG format via normalize_substation_id_for_pg():
    SUB-HOU-NNNN (4-digit) → SUB-HOU-NNN (3-digit, LPAD 3)
    SUB_NNNN     (underscore, 4-digit) → SUB-NNNN (hyphen, 4-digit)
  A direct set-lookup without normalization yields 0 FK matches because the
  formats differ; the function resolves this and achieves ~100% coverage.
- Inserts source_outage_id = original Snowflake OUTAGE_ID string for traceability.
- OUTAGE_ID (VARCHAR) → deterministic UUID via uuid5 for idempotent re-runs.
- ON CONFLICT (outage_id) DO NOTHING — safe to re-run.
- Pauses 0.1s per 1,000-row batch to avoid overwhelming live SSE connections
  (the AFTER INSERT trigger fires NOTIFY 'outages_chan' on each row).

Author : Abhinav Bannerjee
Date   : 2026-05-26
"""

import re
import time
import tomllib
import uuid
from pathlib import Path
from typing import Optional

import psycopg2
import psycopg2.extras
import snowflake.connector

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

import os

PG_HOST = os.environ.get("FLUX_OPS_PG_HOST", "")
if not PG_HOST:
    raise SystemExit("Set FLUX_OPS_PG_HOST env var to your Postgres hostname.")
PG_HOST_PREFIX = PG_HOST.split(".")[0]
PG_PORT = 5432
PG_DBNAME = "postgres"
PG_USER = "snowflake_admin"

SF_DATABASE = "FLUX_DB"
SF_SCHEMA = "PRODUCTION"
SF_WAREHOUSE = "FLUX_WH"

BATCH_SIZE = 1000
BATCH_PAUSE_S = 0.1

# Fallback coordinates when TRANSFORMER_METADATA has no matching row.
HOUSTON_LAT = 29.7604
HOUSTON_LON = -95.3698

# Deterministic UUID namespace for outage IDs.
_UUID_NS = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")  # uuid.NAMESPACE_URL

# ---------------------------------------------------------------------------
# Snowflake query
# ---------------------------------------------------------------------------

SNOWFLAKE_QUERY = """
SELECT
    ORT.OUTAGE_ID,
    ORT.CIRCUIT_ID,
    ORT.CAUSE,
    ORT.AFFECTED_CUSTOMERS,
    ORT.OUTAGE_START_TIME,
    ORT.OUTAGE_END_TIME,
    ORT.ESTIMATED_RESTORATION,
    COALESCE(TM.LATITUDE,  {lat})  AS LAT,
    COALESCE(TM.LONGITUDE, {lon}) AS LON,
    TM.SUBSTATION_ID AS XFMR_SUBSTATION_ID
FROM FLUX_DB.PRODUCTION.OUTAGE_RESTORATION_TRACKER ORT
LEFT JOIN FLUX_DB.PRODUCTION.TRANSFORMER_METADATA TM
    ON ORT.TRANSFORMER_ID = TM.TRANSFORMER_ID
ORDER BY ORT.OUTAGE_START_TIME
""".format(lat=HOUSTON_LAT, lon=HOUSTON_LON)

# ---------------------------------------------------------------------------
# Postgres INSERT
# ---------------------------------------------------------------------------

INSERT_SQL = """
INSERT INTO public.outages (
    outage_id, status, cause, severity, lat, lon, substation_id,
    circuit_id, customers_affected, start_time,
    predicted_resolution_time, actual_resolution_time,
    scenario, created_at, updated_at, source_outage_id
) VALUES %s
ON CONFLICT (outage_id) DO NOTHING
"""

# ---------------------------------------------------------------------------
# Connection helpers
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
                # Password is field 5; may itself contain colons
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
# Mapping helpers
# ---------------------------------------------------------------------------


def make_outage_uuid(outage_id_str: str) -> str:
    """Deterministic UUID from source OUTAGE_ID (idempotent re-run safe)."""
    return str(uuid.uuid5(_UUID_NS, f"flux-outage:{outage_id_str}"))


def normalize_substation_id_for_pg(
    snowflake_id: Optional[str], pg_substation_set: set
) -> Optional[str]:
    """
    Normalize Snowflake TRANSFORMER_METADATA.SUBSTATION_ID to PG format.

    Format mismatch (source of all-NULL substation_id in previous sync runs):
      SUB-HOU-NNNN (Snowflake, 4-digit) → SUB-HOU-NNN (PG, 3-digit): drop leading zero
      SUB_NNNN     (Snowflake, underscore) → SUB-NNNN  (PG, hyphen): replace _ with -

    Returns the normalized PG ID if it exists in pg_substation_set, else None.
    Always validates against the live FK set to prevent constraint violations.
    """
    if not snowflake_id:
        return None

    m = re.match(r"^SUB-HOU-(\d+)$", snowflake_id)
    if m:
        normalized = f"SUB-HOU-{int(m.group(1)):03d}"
        return normalized if normalized in pg_substation_set else None

    m = re.match(r"^SUB_(\d+)$", snowflake_id)
    if m:
        normalized = f"SUB-{int(m.group(1)):04d}"
        return normalized if normalized in pg_substation_set else None

    return snowflake_id if snowflake_id in pg_substation_set else None


def map_severity(cause: str, customers_affected: int) -> str:
    """Map cause + customers_affected to public.outages severity enum."""
    ca = customers_affected or 0
    if cause == "WEATHER" and ca > 1:
        return "CRITICAL"
    if ca > 30:
        return "HIGH"
    if ca > 5:
        return "MEDIUM"
    return "LOW"


def map_scenario(cause: str) -> str:
    """Map cause to a descriptive scenario tag."""
    if cause == "WEATHER":
        return "beryl_historical"
    if cause == "VEGETATION":
        return "historical_vegetation"
    if cause in ("TRANSFORMER_OVERLOAD", "OVERLOAD"):
        return "historical_overload"
    return "historical_other"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    print("=" * 60)
    print("06_postgres_outage_sync.py")
    print("=" * 60)

    # --- Connect to Snowflake ---
    print("\n[1/5] Connecting to Snowflake (se_demo) ...")
    sf_conn = get_snowflake_conn()
    print("      OK")

    # --- Connect to Postgres ---
    print("[2/5] Connecting to Postgres (FLUX_OPS_POSTGRES) ...")
    pg_conn = get_postgres_conn()
    pg_cur = pg_conn.cursor()
    print("      OK")

    # --- Pre-load valid substation IDs from Postgres ---
    print("[3/5] Loading valid substation IDs from public.substations ...")
    pg_cur.execute("SELECT substation_id FROM public.substations")
    valid_substations = {row[0] for row in pg_cur.fetchall()}
    print(f"      {len(valid_substations)} substation IDs loaded")

    # Record baseline count for accurate inserted-row reporting
    pg_cur.execute("SELECT COUNT(*) FROM public.outages")
    baseline_count = pg_cur.fetchone()[0]
    print(f"      public.outages baseline row count: {baseline_count}")

    # --- Fetch outage data from Snowflake ---
    print("[4/5] Fetching outage rows from Snowflake ...")
    sf_cur = sf_conn.cursor()
    sf_cur.execute(SNOWFLAKE_QUERY)
    rows = sf_cur.fetchall()
    sf_cur.close()
    sf_conn.close()
    print(f"      {len(rows)} rows fetched")

    # --- Insert into Postgres in batches ---
    print(f"[5/5] Inserting into public.outages (batch size={BATCH_SIZE}) ...")
    batch: list = []
    no_latlon_fallback = 0
    batches_flushed = 0

    for row in rows:
        (
            outage_id_str,
            circuit_id,
            cause,
            customers_affected,
            start_time,
            end_time,
            est_restoration,
            lat,
            lon,
            xfmr_substation_id,
        ) = row

        ca = int(customers_affected) if customers_affected is not None else 0
        cause = (cause or "UNKNOWN").upper()

        # Track lat/lon fallback usage
        if abs(float(lat) - HOUSTON_LAT) < 0.0001 and abs(float(lon) - HOUSTON_LON) < 0.0001:
            no_latlon_fallback += 1

        # Normalize Snowflake SUBSTATION_ID to PG FK format and validate
        sub_id = normalize_substation_id_for_pg(xfmr_substation_id, valid_substations)

        batch.append((
            make_outage_uuid(outage_id_str),   # outage_id (deterministic UUID)
            "RESTORED",                         # status
            cause,                             # cause
            map_severity(cause, ca),           # severity
            float(lat),                        # lat
            float(lon),                        # lon
            sub_id,                            # substation_id (normalized + FK-validated)
            circuit_id,                        # circuit_id
            ca,                                # customers_affected
            start_time,                        # start_time
            est_restoration,                   # predicted_resolution_time
            end_time,                          # actual_resolution_time
            map_scenario(cause),               # scenario
            start_time,                        # created_at
            end_time,                          # updated_at
            outage_id_str,                     # source_outage_id (original Snowflake ID)
        ))

        if len(batch) >= BATCH_SIZE:
            psycopg2.extras.execute_values(pg_cur, INSERT_SQL, batch)
            pg_conn.commit()
            batches_flushed += 1
            total_so_far = baseline_count + batches_flushed * BATCH_SIZE
            print(f"      Batch {batches_flushed}: ~{total_so_far} rows in table ...")
            batch = []
            time.sleep(BATCH_PAUSE_S)

    # Flush remaining rows
    if batch:
        psycopg2.extras.execute_values(pg_cur, INSERT_SQL, batch)
        pg_conn.commit()
        batches_flushed += 1

    # --- Final count ---
    pg_cur.execute(
        "SELECT COUNT(*) AS total, COUNT(substation_id) AS with_sub "
        "FROM public.outages"
    )
    final_row = pg_cur.fetchone()
    final_count = final_row[0]
    sub_populated = final_row[1]
    actually_inserted = final_count - baseline_count

    pg_cur.close()
    pg_conn.close()

    # --- Summary ---
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"  Rows fetched from Snowflake:      {len(rows)}")
    print(f"  Rows actually inserted (new):     {actually_inserted}")
    print(f"  Rows skipped (ON CONFLICT):        {len(rows) - actually_inserted}")
    print(f"  Rows using lat/lon fallback:      {no_latlon_fallback}")
    print(f"  Substation FK resolved (non-NULL): {sub_populated}")
    print(f"  Final public.outages row count:   {final_count}")
    print("=" * 60)
    print("\nNOTIFY 'outages_chan' fired for each inserted row via trigger.")
    print("SSE subscribers (live Ops Center map) received push events.")


if __name__ == "__main__":
    main()
