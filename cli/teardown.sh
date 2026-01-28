#!/bin/bash
# =============================================================================
# Flux Utility Solutions - Teardown Script
# =============================================================================
# Completely removes all Flux resources from a Snowflake account
#
# Usage:
#   ./teardown.sh                    # Teardown dev environment
#   ./teardown.sh --env prod         # Teardown production (requires confirm)
#   ./teardown.sh --database FLUX_X  # Teardown specific database
#   ./teardown.sh --force            # Skip confirmation prompts
#
# What gets removed:
#   - Database and all schemas
#   - Warehouses
#   - Compute pools (if empty)
#   - SPCS services
#   - PostgreSQL instances
#   - Roles (Flux-specific only)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
ENV="dev"
DATABASE=""
CONNECTION=""
FORCE=false

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

show_help() {
    cat << EOF
Flux Utility Solutions - Teardown

USAGE:
    ./teardown.sh [OPTIONS]

OPTIONS:
    --env ENV           Environment: dev, staging, prod (default: dev)
    --database NAME     Specific database to drop
    --connection NAME   Snowflake connection name
    --force             Skip confirmation prompts
    --help              Show this help

EXAMPLES:
    ./teardown.sh                     # Teardown FLUX_DEV
    ./teardown.sh --env staging       # Teardown FLUX_STAGING
    ./teardown.sh --database FLUX_X   # Teardown specific database
    ./teardown.sh --force             # No confirmation

EOF
}

confirm_teardown() {
    if $FORCE; then
        return 0
    fi
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                    ⚠️  WARNING ⚠️                              ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║  This will PERMANENTLY DELETE:                                ║"
    echo "║    • Database: $DATABASE"
    echo "║    • All tables, views, and data                              ║"
    echo "║    • Cortex services (Search, Agents)                         ║"
    echo "║    • SPCS services and compute pools                          ║"
    echo "║    • PostgreSQL instances                                     ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    
    read -p "Type 'DELETE' to confirm: " confirm
    if [[ "$confirm" != "DELETE" ]]; then
        log_info "Teardown cancelled"
        exit 0
    fi
}

run_sql() {
    local sql="$1"
    local conn_flag=""
    [[ -n "$CONNECTION" ]] && conn_flag="-c $CONNECTION"
    
    snow sql $conn_flag -q "$sql" 2>/dev/null || true
}

teardown_spcs() {
    log_info "Stopping SPCS services..."
    
    # Stop services
    run_sql "ALTER SERVICE IF EXISTS ${DATABASE}.APPLICATIONS.FLUX_OPS_CENTER_SERVICE SUSPEND;"
    run_sql "ALTER SERVICE IF EXISTS ${DATABASE}.APPLICATIONS.FLUX_DATA_FORGE_SERVICE SUSPEND;"
    
    # Drop services
    run_sql "DROP SERVICE IF EXISTS ${DATABASE}.APPLICATIONS.FLUX_OPS_CENTER_SERVICE;"
    run_sql "DROP SERVICE IF EXISTS ${DATABASE}.APPLICATIONS.FLUX_DATA_FORGE_SERVICE;"
    
    log_success "SPCS services removed"
}

teardown_postgres() {
    log_info "Removing PostgreSQL instances..."
    
    # Stop and drop postgres
    run_sql "ALTER POSTGRESQL INSTANCE IF EXISTS ${DATABASE}.PRODUCTION.FLUX_OPERATIONS_POSTGRES SUSPEND;"
    run_sql "DROP POSTGRESQL INSTANCE IF EXISTS ${DATABASE}.PRODUCTION.FLUX_OPERATIONS_POSTGRES;"
    
    log_success "PostgreSQL instances removed"
}

teardown_compute_pools() {
    log_info "Removing compute pools..."
    
    # Suspend and drop compute pools
    run_sql "ALTER COMPUTE POOL IF EXISTS FLUX_INTERACTIVE_POOL STOP ALL;"
    run_sql "ALTER COMPUTE POOL IF EXISTS FLUX_INTERACTIVE_POOL SUSPEND;"
    run_sql "DROP COMPUTE POOL IF EXISTS FLUX_INTERACTIVE_POOL;"
    
    run_sql "ALTER COMPUTE POOL IF EXISTS FLUX_DATA_FORGE_POOL STOP ALL;"
    run_sql "ALTER COMPUTE POOL IF EXISTS FLUX_DATA_FORGE_POOL SUSPEND;"
    run_sql "DROP COMPUTE POOL IF EXISTS FLUX_DATA_FORGE_POOL;"
    
    log_success "Compute pools removed"
}

teardown_warehouses() {
    log_info "Removing warehouses..."
    
    run_sql "DROP WAREHOUSE IF EXISTS ${DATABASE/FLUX_/FLUX_}_WH;"
    run_sql "DROP WAREHOUSE IF EXISTS ${DATABASE/FLUX_/FLUX_}_WH_LARGE;"
    run_sql "DROP WAREHOUSE IF EXISTS FLUX_DEV_MEDIUM;"
    run_sql "DROP WAREHOUSE IF EXISTS FLUX_STAGING_MEDIUM;"
    run_sql "DROP WAREHOUSE IF EXISTS FLUX_PROD_LARGE;"
    run_sql "DROP WAREHOUSE IF EXISTS FLUX_QUICKSTART_WH;"
    
    log_success "Warehouses removed"
}

teardown_database() {
    log_info "Dropping database: $DATABASE"
    
    run_sql "DROP DATABASE IF EXISTS $DATABASE CASCADE;"
    
    log_success "Database removed"
}

teardown_roles() {
    log_info "Removing Flux roles..."
    
    run_sql "DROP ROLE IF EXISTS FLUX_ADMIN_ROLE;"
    run_sql "DROP ROLE IF EXISTS FLUX_USER_ROLE;"
    run_sql "DROP ROLE IF EXISTS FLUX_ANALYST_ROLE;"
    
    log_success "Roles removed"
}

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env)
                ENV="$2"
                shift 2
                ;;
            --database)
                DATABASE="$2"
                shift 2
                ;;
            --connection)
                CONNECTION="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Set database based on environment if not specified
    if [[ -z "$DATABASE" ]]; then
        case "$ENV" in
            dev) DATABASE="FLUX_DEV" ;;
            staging) DATABASE="FLUX_STAGING" ;;
            prod) DATABASE="FLUX_PROD" ;;
            quickstart) DATABASE="FLUX_QUICKSTART" ;;
            *) DATABASE="FLUX_${ENV^^}" ;;
        esac
    fi
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║              Flux Utility Solutions - Teardown                   ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    confirm_teardown
    
    START=$(date +%s)
    
    teardown_spcs
    teardown_postgres
    teardown_compute_pools
    teardown_database
    teardown_warehouses
    teardown_roles
    
    END=$(date +%s)
    
    echo ""
    log_success "Teardown complete! ($(($END - $START)) seconds)"
    echo ""
}

main "$@"
