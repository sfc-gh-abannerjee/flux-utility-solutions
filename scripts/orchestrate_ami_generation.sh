#!/usr/bin/env bash
# orchestrate_ami_generation.sh
# Agent-operator AMI generation orchestrator.
# Emits one stdout line per logical event for live consumption via the `monitor` tool.
#
# Usage:
#   bash orchestrate_ami_generation.sh \
#     --connection se_demo \
#     --run-id "$(date +%Y%m%d_%H%M%S)" \
#     --start-date 2024-07-01 \
#     --total-days 30 \
#     --meter-sample 100000 \
#     [--warehouse FLUX_AMI_GEN_WH] \
#     [--dry-run]
#
# Agent-side operator commands (run via sql_execute):
#   sql_execute "UPDATE FLUX_DB.PRODUCTION.AMI_GENERATION_CONTROL SET CONTROL_VALUE='RUNNING'  WHERE CONTROL_KEY='STATUS'"
#   sql_execute "UPDATE FLUX_DB.PRODUCTION.AMI_GENERATION_CONTROL SET CONTROL_VALUE='PAUSED'   WHERE CONTROL_KEY='STATUS'"
#   sql_execute "UPDATE FLUX_DB.PRODUCTION.AMI_GENERATION_CONTROL SET CONTROL_VALUE='ABORTED'  WHERE CONTROL_KEY='STATUS'"
#   sql_execute "SELECT SYSTEM\$CANCEL_QUERY('<query_id from most recent CHUNK done line>')"
#   sql_execute "ALTER WAREHOUSE FLUX_AMI_GEN_WH SUSPEND"   -- hard kill
#
# Stdout event format (one line per event, line-buffered):
#   [HH:MM:SS] ORCH start   run_id=…  total_days=N  meter_sample=N  start_date=…  warehouse=…  dry_run=…
#   [HH:MM:SS] CHUNK n/N start   run_id=…  day=YYYY-MM-DD
#   [HH:MM:SS] CHUNK n/N done    rows=N  query_id=…  duration_s=N
#   [HH:MM:SS] CHUNK n/N validation=PASS|WARN|FAIL  reason="…"
#   [HH:MM:SS] ORCH halt    control=PAUSED|ABORTED  chunk=N  exiting cleanly
#   [HH:MM:SS] ORCH auto-pause on validation FAIL  chunk=N
#   [HH:MM:SS] ORCH complete  chunks=N  run_id=…
#
# Exit codes:
#   0  — graceful complete or graceful pause (CONTROL_VALUE != RUNNING)
#   1  — snow sql call failed, validation FAIL auto-pause, or unexpected error

set -uo pipefail

# Force line-buffered stdout so the `monitor` tool sees every event in real time.
exec 1> >(stdbuf -oL cat)

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
CONNECTION="se_demo"
RUN_ID=""
START_DATE=""
TOTAL_DAYS=30
METER_SAMPLE=100000
DRY_RUN="FALSE"
WAREHOUSE=""

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --connection)    CONNECTION="$2";    shift 2 ;;
        --run-id)        RUN_ID="$2";        shift 2 ;;
        --start-date)    START_DATE="$2";    shift 2 ;;
        --total-days)    TOTAL_DAYS="$2";    shift 2 ;;
        --meter-sample)  METER_SAMPLE="$2";  shift 2 ;;
        --warehouse|-w)  WAREHOUSE="$2";     shift 2 ;;
        --dry-run)       DRY_RUN="TRUE";     shift   ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 --connection NAME --run-id ID --start-date YYYY-MM-DD [--total-days N] [--meter-sample N] [--warehouse WH] [--dry-run]" >&2
            exit 1
            ;;
    esac
done

# Apply defaults that depend on parsed args
WAREHOUSE="${WAREHOUSE:-FLUX_AMI_GEN_WH}"

# Validate required args
if [[ -z "$RUN_ID" || -z "$START_DATE" ]]; then
    echo "ERROR: --run-id and --start-date are required." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# emit: print a timestamped event line to stdout (line-buffered)
emit() {
    echo "[$(date +%H:%M:%S)] $*"
}

# control_status: read CONTROL_VALUE from AMI_GENERATION_CONTROL
control_status() {
    snow sql \
        -q "USE WAREHOUSE $WAREHOUSE; SELECT CONTROL_VALUE FROM FLUX_DB.PRODUCTION.AMI_GENERATION_CONTROL WHERE CONTROL_KEY='STATUS'" \
        --format=plain \
        --connection "$CONNECTION" 2>/dev/null \
        | tail -n 1 \
        | tr -d '[:space:]'
}

# advance_date: add N days to a YYYY-MM-DD date (macOS + Linux compatible)
advance_date() {
    local base_date="$1"
    local days="$2"
    # macOS: date -j -v+Nd -f "%Y-%m-%d"
    # Linux: date -d "$base_date + $days day"
    if date -j -v "+${days}d" -f "%Y-%m-%d" "$base_date" +"%Y-%m-%d" 2>/dev/null; then
        return 0
    fi
    date -d "$base_date + $days day" +"%Y-%m-%d"
}

# ---------------------------------------------------------------------------
# Main orchestration loop
# ---------------------------------------------------------------------------

emit "ORCH start  run_id=$RUN_ID  total_days=$TOTAL_DAYS  meter_sample=$METER_SAMPLE  start_date=$START_DATE  warehouse=$WAREHOUSE  dry_run=$DRY_RUN"

for ((i=1; i<=TOTAL_DAYS; i++)); do
    DAY=$(advance_date "$START_DATE" $((i-1)))
    FROM_TS="${DAY} 00:00:00"
    TO_TS="${DAY} 23:45:00"   # last 15-min slot in a full day

    # 1. Check control flag BEFORE every chunk — graceful pause/abort
    STATUS=$(control_status)
    if [[ "$STATUS" != "RUNNING" ]]; then
        emit "ORCH halt  control=$STATUS  chunk=$i  exiting cleanly"
        exit 0
    fi

    emit "CHUNK $i/$TOTAL_DAYS start  run_id=$RUN_ID  day=$DAY"

    # 2. Run the chunk via GENERATE_AMI_CHUNK
    CALL_RESULT=$(snow sql \
        -q "USE WAREHOUSE $WAREHOUSE; CALL FLUX_DB.PRODUCTION.GENERATE_AMI_CHUNK(
                '$RUN_ID',
                $i,
                '$FROM_TS'::TIMESTAMP_NTZ,
                '$TO_TS'::TIMESTAMP_NTZ,
                $METER_SAMPLE,
                $DRY_RUN
            )" \
        --format=json \
        --connection "$CONNECTION" 2>&1)
    RC=$?

    if [[ $RC -ne 0 ]]; then
        emit "CHUNK $i/$TOTAL_DAYS FAILED  rc=$RC  error=\"$(echo "$CALL_RESULT" | tr '\n' ' ' | cut -c1-240)\""
        exit 1
    fi

    ROWS=$(echo "$CALL_RESULT"     | jq -r '.[0].ROWS_INSERTED    // 0'       2>/dev/null || echo 0)
    QID=$(echo "$CALL_RESULT"      | jq -r '.[0].QUERY_ID          // "unknown"' 2>/dev/null || echo unknown)
    DUR=$(echo "$CALL_RESULT"      | jq -r '.[0].DURATION_SECONDS  // 0'       2>/dev/null || echo 0)

    emit "CHUNK $i/$TOTAL_DAYS done   rows=$ROWS  query_id=$QID  duration_s=$DUR"

    # 3. Validate the chunk immediately
    VAL_RESULT=$(snow sql \
        -q "USE WAREHOUSE $WAREHOUSE; CALL FLUX_DB.PRODUCTION.VALIDATE_AMI_CHUNK('$RUN_ID', $i)" \
        --format=json \
        --connection "$CONNECTION" 2>&1)
    VAL_RC=$?

    if [[ $VAL_RC -ne 0 ]]; then
        emit "CHUNK $i/$TOTAL_DAYS validation=ERROR  reason=\"validate call failed: $(echo "$VAL_RESULT" | tr '\n' ' ' | cut -c1-200)\""
        # Treat a failed validation call as FAIL
        snow sql \
            -q "USE WAREHOUSE $WAREHOUSE; UPDATE FLUX_DB.PRODUCTION.AMI_GENERATION_CONTROL SET CONTROL_VALUE='PAUSED', UPDATED_AT=CURRENT_TIMESTAMP() WHERE CONTROL_KEY='STATUS'" \
            --connection "$CONNECTION" >/dev/null 2>&1
        emit "ORCH auto-pause on validation call error  chunk=$i"
        exit 1
    fi

    VERDICT=$(echo "$VAL_RESULT" | jq -r '.[0].VERDICT // "UNKNOWN"' 2>/dev/null || echo UNKNOWN)
    REASON=$(echo "$VAL_RESULT"  | jq -r '.[0].REASON  // ""'        2>/dev/null || echo '')

    emit "CHUNK $i/$TOTAL_DAYS validation=$VERDICT  reason=\"$REASON\""

    # 4. Auto-pause on FAIL; continue on WARN or PASS
    if [[ "$VERDICT" == "FAIL" ]]; then
        snow sql \
            -q "USE WAREHOUSE $WAREHOUSE; UPDATE FLUX_DB.PRODUCTION.AMI_GENERATION_CONTROL SET CONTROL_VALUE='PAUSED', UPDATED_AT=CURRENT_TIMESTAMP() WHERE CONTROL_KEY='STATUS'" \
            --connection "$CONNECTION" >/dev/null 2>&1
        emit "ORCH auto-pause on validation FAIL  chunk=$i"
        exit 1
    fi

    # 5. Brief breathing room so the agent sees events in distinct turns
    sleep 1
done

emit "ORCH complete  chunks=$TOTAL_DAYS  run_id=$RUN_ID"
exit 0
