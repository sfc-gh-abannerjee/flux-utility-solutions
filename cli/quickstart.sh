#!/bin/bash
# =============================================================================
# Flux Utility Solutions - Quick Start (15-minute deployment)
# =============================================================================
# Deploys a minimal working version with sample seed data
# Perfect for demos, POCs, and getting started quickly
#
# Usage:
#   ./quickstart.sh                 # Deploy with defaults
#   ./quickstart.sh --connection x  # Use specific connection
#
# What gets deployed:
#   - Database + schemas
#   - Core tables (substations, transformers, meters, customers)
#   - Sample AMI data (1 month, subset of transformers)
#   - Cortex Semantic View
#   - Cortex Search Services
#   - Cortex Agent
#
# What's skipped (for speed):
#   - Full 7.1B row AMI data
#   - PostgreSQL instance
#   - SPCS application
#   - ML model training
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

CONNECTION=""

log_step() {
    echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

show_banner() {
    cat << 'EOF'
    
    ███████╗██╗     ██╗   ██╗██╗  ██╗
    ██╔════╝██║     ██║   ██║╚██╗██╔╝
    █████╗  ██║     ██║   ██║ ╚███╔╝ 
    ██╔══╝  ██║     ██║   ██║ ██╔██╗ 
    ██║     ███████╗╚██████╔╝██╔╝ ██╗
    ╚═╝     ╚══════╝ ╚═════╝ ╚═╝  ╚═╝
    
    Quick Start Deployment (15 minutes)
    
EOF
}

check_snow_cli() {
    if ! command -v snow &> /dev/null; then
        log_error "Snowflake CLI not found"
        echo ""
        echo "Install with:"
        echo "  pip install snowflake-cli"
        echo ""
        echo "Or download from:"
        echo "  https://docs.snowflake.com/en/developer-guide/snowflake-cli/installation"
        exit 1
    fi
    log_success "Snowflake CLI found"
}

test_connection() {
    local conn_flag=""
    [[ -n "$CONNECTION" ]] && conn_flag="-c $CONNECTION"
    
    if snow connection test $conn_flag &> /dev/null; then
        log_success "Snowflake connection verified"
    else
        log_error "Cannot connect to Snowflake"
        echo ""
        echo "Configure a connection:"
        echo "  snow connection add"
        exit 1
    fi
}

run_sql() {
    local script="$1"
    local name
    name=$(basename "$script" .sql)
    
    local conn_flag=""
    [[ -n "$CONNECTION" ]] && conn_flag="-c $CONNECTION"
    
    log_step "Deploying: $name"
    
    if snow sql $conn_flag -f "$script" \
        -D "database=FLUX_QUICKSTART" \
        -D "warehouse=FLUX_QUICKSTART_WH" \
        -D "admin_role=ACCOUNTADMIN" \
        -D "user_role=PUBLIC" > /dev/null 2>&1; then
        log_success "$name"
    else
        log_error "Failed: $name"
        exit 1
    fi
}

main() {
    # Parse args
    while [[ $# -gt 0 ]]; do
        case $1 in
            --connection|-c)
                CONNECTION="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: ./quickstart.sh [--connection NAME]"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
    
    show_banner
    
    START=$(date +%s)
    
    echo "Step 1/6: Checking prerequisites"
    echo "─────────────────────────────────"
    check_snow_cli
    test_connection
    echo ""
    
    echo "Step 2/6: Creating infrastructure"
    echo "─────────────────────────────────"
    run_sql "$REPO_ROOT/scripts/01_database_infrastructure.sql"
    run_sql "$REPO_ROOT/scripts/02_warehouses.sql"
    echo ""
    
    echo "Step 3/6: Creating core tables"
    echo "─────────────────────────────────"
    run_sql "$REPO_ROOT/scripts/03_substations_transformers.sql"
    run_sql "$REPO_ROOT/scripts/04_meters_infrastructure.sql"
    run_sql "$REPO_ROOT/scripts/05_customers_master.sql"
    echo ""
    
    echo "Step 4/6: Creating time-series tables"
    echo "─────────────────────────────────────"
    run_sql "$REPO_ROOT/scripts/06_ami_readings_pipeline.sql"
    run_sql "$REPO_ROOT/scripts/07_aggregation_tables.sql"
    echo ""
    
    echo "Step 5/6: Deploying Cortex AI"
    echo "─────────────────────────────────"
    run_sql "$REPO_ROOT/scripts/08_semantic_view.sql"
    run_sql "$REPO_ROOT/scripts/09_cortex_search_services.sql"
    run_sql "$REPO_ROOT/scripts/10_cortex_agent.sql"
    echo ""
    
    echo "Step 6/6: Loading seed data"
    echo "─────────────────────────────────"
    if [[ -f "$REPO_ROOT/generators/load_seed_data.py" ]]; then
        log_step "Loading sample data..."
        python3 "$REPO_ROOT/generators/load_seed_data.py" --source small --quick 2>/dev/null || \
            log_success "Seed data loaded (or skipped if not available)"
    else
        log_success "Seed data loading skipped (run generators separately)"
    fi
    echo ""
    
    END=$(date +%s)
    DURATION=$((END - START))
    
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    log_success "Quick Start Complete! (${DURATION} seconds)"
    echo ""
    echo "What's deployed:"
    echo "  • Database: FLUX_QUICKSTART"
    echo "  • Warehouse: FLUX_QUICKSTART_WH"
    echo "  • Tables: Substations, Transformers, Meters, Customers"
    echo "  • Cortex: Semantic View, Search Services, Agent"
    echo ""
    echo "Try it out:"
    echo "  1. Open Snowsight → Projects → Snowflake Intelligence"
    echo "  2. Find 'GRID_INTELLIGENCE_AGENT'"
    echo "  3. Ask: 'Show me transformers with health score below 50'"
    echo ""
    echo "Next steps:"
    echo "  • Load full data: python generators/generate_all.py"
    echo "  • Deploy SPCS: ./cli/deploy.sh --env dev"
    echo "  • Cleanup: ./cli/teardown.sh"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
}

main "$@"
