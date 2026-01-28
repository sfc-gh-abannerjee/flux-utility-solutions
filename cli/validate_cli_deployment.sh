#!/bin/bash
# =============================================================================
# validate_cli_deployment.sh
# Validates CLI deployment path results
# =============================================================================
# Usage:
#   ./validate_cli_deployment.sh                    # Validate FLUX_DEV
#   ./validate_cli_deployment.sh FLUX_PROD          # Validate specific database
#   ./validate_cli_deployment.sh FLUX_PROD myconn   # With specific connection
# =============================================================================

set -e

DATABASE=${1:-"FLUX_DEV"}
CONNECTION=${2:-""}

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║          CLI Deployment Validation                               ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  Database: $(printf '%-54s' "$DATABASE")  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

CONN_FLAG=""
[[ -n "$CONNECTION" ]] && CONN_FLAG="-c $CONNECTION"

# Function to run SQL and check result
check_sql() {
    local description="$1"
    local sql="$2"
    local expected="$3"
    
    result=$(snow sql $CONN_FLAG -q "$sql" -o json 2>/dev/null | head -1) || result=""
    
    if [[ -n "$result" && "$result" != "[]" ]]; then
        echo -e "${GREEN}✓${NC} $description"
        return 0
    else
        echo -e "${RED}✗${NC} $description"
        return 1
    fi
}

# Function to get count
get_count() {
    local sql="$1"
    snow sql $CONN_FLAG -q "$sql" -o json 2>/dev/null | grep -o '"[0-9]*"' | head -1 | tr -d '"' || echo "0"
}

echo "Step 1: Database & Schemas"
echo "────────────────────────────"
check_sql "Database exists" "SELECT 1 FROM INFORMATION_SCHEMA.DATABASES WHERE DATABASE_NAME = '$DATABASE'" "1"

SCHEMA_COUNT=$(get_count "SELECT COUNT(*) FROM $DATABASE.INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME IN ('PRODUCTION','APPLICATIONS','RAW','ML','ARCHIVE')")
if [[ "$SCHEMA_COUNT" -ge 5 ]]; then
    echo -e "${GREEN}✓${NC} Required schemas exist ($SCHEMA_COUNT/5)"
else
    echo -e "${RED}✗${NC} Missing schemas ($SCHEMA_COUNT/5)"
fi
echo ""

echo "Step 2: Core Tables"
echo "────────────────────────────"
TABLE_COUNT=$(get_count "SELECT COUNT(*) FROM $DATABASE.INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'PRODUCTION' AND TABLE_TYPE = 'BASE TABLE'")
if [[ "$TABLE_COUNT" -ge 5 ]]; then
    echo -e "${GREEN}✓${NC} PRODUCTION tables exist ($TABLE_COUNT tables)"
else
    echo -e "${YELLOW}⚠${NC} Limited tables in PRODUCTION ($TABLE_COUNT tables)"
fi

# Check specific core tables
for table in SUBSTATIONS TRANSFORMER_METADATA METER_INFRASTRUCTURE CUSTOMERS_MASTER_DATA AMI_INTERVAL_READINGS; do
    check_sql "  - $table" "SELECT 1 FROM $DATABASE.INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='PRODUCTION' AND TABLE_NAME='$table'" "1" || true
done
echo ""

echo "Step 3: Aggregation Tables"
echo "────────────────────────────"
for table in TRANSFORMER_HOURLY_LOAD OUTAGE_EVENTS VOLTAGE_SAG_EVENTS; do
    check_sql "  - $table" "SELECT 1 FROM $DATABASE.INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='PRODUCTION' AND TABLE_NAME='$table'" "1" || true
done
echo ""

echo "Step 4: Views"
echo "────────────────────────────"
VIEW_COUNT=$(get_count "SELECT COUNT(*) FROM $DATABASE.INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = 'APPLICATIONS'")
if [[ "$VIEW_COUNT" -ge 1 ]]; then
    echo -e "${GREEN}✓${NC} APPLICATIONS views exist ($VIEW_COUNT views)"
else
    echo -e "${YELLOW}⚠${NC} No views in APPLICATIONS"
fi
echo ""

echo "Step 5: Cortex Services (Manual Check)"
echo "────────────────────────────"
echo "  Run manually to verify:"
echo "    SHOW CORTEX SEARCH SERVICES IN $DATABASE.APPLICATIONS;"
echo "    SHOW SEMANTIC VIEWS IN $DATABASE.APPLICATIONS;"
echo "    SHOW CORTEX AGENTS IN $DATABASE.APPLICATIONS;"
echo ""

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                    Summary                                       ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  Tables: $(printf '%-58s' "$TABLE_COUNT")  ║"
echo "║  Views:  $(printf '%-58s' "$VIEW_COUNT")  ║"
echo "║  Schemas: $(printf '%-57s' "$SCHEMA_COUNT/5")  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "For full validation, run:"
echo "  python $SCRIPT_DIR/validate.py --env dev --connection $CONNECTION"
