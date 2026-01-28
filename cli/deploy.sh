#!/bin/bash
# =============================================================================
# Flux Utility Solutions - Full Deployment Script
# =============================================================================
# Deploys the complete Flux ecosystem to a Snowflake account
# 
# Usage:
#   ./deploy.sh                    # Deploy with defaults (dev environment)
#   ./deploy.sh --env prod         # Deploy to production
#   ./deploy.sh --env staging      # Deploy to staging
#   ./deploy.sh --connection myconn # Use specific Snowflake connection
#   ./deploy.sh --skip-data        # Skip seed data loading
#   ./deploy.sh --help             # Show help
#
# Prerequisites:
#   - Snowflake CLI (snow) installed
#   - Valid Snowflake connection configured
#   - Python 3.10+ (for data generation)
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Default configuration
ENV="dev"
CONNECTION=""
SKIP_DATA=false
SKIP_SPCS=false
VERBOSE=false

# =============================================================================
# Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
Flux Utility Solutions - Full Deployment

USAGE:
    ./deploy.sh [OPTIONS]

OPTIONS:
    --env ENV           Environment: dev, staging, prod (default: dev)
    --connection NAME   Snowflake connection name (from ~/.snowflake/connections.toml)
    --skip-data         Skip seed data loading
    --skip-spcs         Skip SPCS deployment (compute pools, services)
    --verbose           Enable verbose output
    --help              Show this help message

EXAMPLES:
    # Deploy to dev environment with default connection
    ./deploy.sh

    # Deploy to production with specific connection
    ./deploy.sh --env prod --connection prod_admin

    # Deploy infrastructure only (no data)
    ./deploy.sh --skip-data

DEPLOYMENT PHASES:
    1. Infrastructure Setup (database, schemas, roles, warehouses)
    2. Core Tables (substations, transformers, meters, customers)
    3. Time-Series Tables (AMI readings, dynamic tables)
    4. Cortex AI Services (semantic view, search, agents)
    5. ML Pipeline (feature tables, model registry)
    6. PostgreSQL Instance (managed Postgres + CDC)
    7. SPCS Application (compute pools, services)
    8. Seed Data Loading (optional)
    9. Validation

ESTIMATED TIME:
    - Infrastructure only: ~10 minutes
    - With seed data: ~20 minutes
    - With SPCS: ~30 minutes

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check snow CLI
    if ! command -v snow &> /dev/null; then
        log_error "Snowflake CLI (snow) not found. Install with: pip install snowflake-cli"
        exit 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 not found. Please install Python 3.10+"
        exit 1
    fi
    
    # Check connection
    if [[ -n "$CONNECTION" ]]; then
        if ! snow connection test -c "$CONNECTION" &> /dev/null; then
            log_error "Cannot connect to Snowflake with connection: $CONNECTION"
            exit 1
        fi
        log_success "Snowflake connection verified: $CONNECTION"
    else
        if ! snow connection test &> /dev/null; then
            log_error "Cannot connect to Snowflake with default connection"
            log_info "Configure with: snow connection add"
            exit 1
        fi
        log_success "Snowflake connection verified (default)"
    fi
}

load_environment() {
    local env_file="$SCRIPT_DIR/config/${ENV}.env"
    
    if [[ -f "$env_file" ]]; then
        log_info "Loading environment: $ENV"
        # shellcheck source=/dev/null
        source "$env_file"
    else
        log_warn "Environment file not found: $env_file"
        log_info "Using default configuration"
        
        # Set defaults based on environment
        case "$ENV" in
            dev)
                DATABASE="${DATABASE:-FLUX_DEV}"
                WAREHOUSE="${WAREHOUSE:-FLUX_DEV_MEDIUM}"
                ADMIN_ROLE="${ADMIN_ROLE:-FLUX_ADMIN_ROLE}"
                USER_ROLE="${USER_ROLE:-FLUX_USER_ROLE}"
                ;;
            staging)
                DATABASE="${DATABASE:-FLUX_STAGING}"
                WAREHOUSE="${WAREHOUSE:-FLUX_STAGING_MEDIUM}"
                ADMIN_ROLE="${ADMIN_ROLE:-FLUX_ADMIN_ROLE}"
                USER_ROLE="${USER_ROLE:-FLUX_USER_ROLE}"
                ;;
            prod)
                DATABASE="${DATABASE:-FLUX_PROD}"
                WAREHOUSE="${WAREHOUSE:-FLUX_PROD_LARGE}"
                ADMIN_ROLE="${ADMIN_ROLE:-FLUX_ADMIN_ROLE}"
                USER_ROLE="${USER_ROLE:-FLUX_USER_ROLE}"
                ;;
        esac
    fi
    
    log_info "Configuration:"
    log_info "  DATABASE: $DATABASE"
    log_info "  WAREHOUSE: $WAREHOUSE"
    log_info "  ADMIN_ROLE: $ADMIN_ROLE"
}

run_sql_script() {
    local script_path="$1"
    local script_name
    script_name=$(basename "$script_path")
    
    log_info "Executing: $script_name"
    
    local conn_flag=""
    if [[ -n "$CONNECTION" ]]; then
        conn_flag="-c $CONNECTION"
    fi
    
    # Use snow sql with variable substitution
    if $VERBOSE; then
        snow sql $conn_flag -f "$script_path" \
            -D "database=$DATABASE" \
            -D "warehouse=$WAREHOUSE" \
            -D "admin_role=$ADMIN_ROLE" \
            -D "user_role=$USER_ROLE"
    else
        snow sql $conn_flag -f "$script_path" \
            -D "database=$DATABASE" \
            -D "warehouse=$WAREHOUSE" \
            -D "admin_role=$ADMIN_ROLE" \
            -D "user_role=$USER_ROLE" > /dev/null 2>&1
    fi
    
    if [[ $? -eq 0 ]]; then
        log_success "Completed: $script_name"
    else
        log_error "Failed: $script_name"
        return 1
    fi
}

deploy_infrastructure() {
    log_info "=========================================="
    log_info "Phase 1: Infrastructure Setup"
    log_info "=========================================="
    
    run_sql_script "$REPO_ROOT/scripts/01_database_infrastructure.sql"
    run_sql_script "$REPO_ROOT/scripts/02_warehouses.sql"
}

deploy_core_tables() {
    log_info "=========================================="
    log_info "Phase 2: Core Tables"
    log_info "=========================================="
    
    run_sql_script "$REPO_ROOT/scripts/03_substations_transformers.sql"
    run_sql_script "$REPO_ROOT/scripts/04_meters_infrastructure.sql"
    run_sql_script "$REPO_ROOT/scripts/05_customers_master.sql"
}

deploy_timeseries() {
    log_info "=========================================="
    log_info "Phase 3: Time-Series Tables"
    log_info "=========================================="
    
    run_sql_script "$REPO_ROOT/scripts/06_ami_readings_pipeline.sql"
    run_sql_script "$REPO_ROOT/scripts/07_aggregation_tables.sql"
}

deploy_cortex() {
    log_info "=========================================="
    log_info "Phase 4: Cortex AI Services"
    log_info "=========================================="
    
    run_sql_script "$REPO_ROOT/scripts/08_semantic_view.sql"
    run_sql_script "$REPO_ROOT/scripts/09_cortex_search_services.sql"
    run_sql_script "$REPO_ROOT/scripts/10_cortex_agent.sql"
}

deploy_ml() {
    log_info "=========================================="
    log_info "Phase 5: ML Pipeline"
    log_info "=========================================="
    
    run_sql_script "$REPO_ROOT/scripts/11_ml_feature_tables.sql"
}

deploy_postgres() {
    log_info "=========================================="
    log_info "Phase 6: PostgreSQL Instance"
    log_info "=========================================="
    
    run_sql_script "$REPO_ROOT/scripts/12_postgres_instance.sql"
}

deploy_spcs() {
    if $SKIP_SPCS; then
        log_warn "Skipping SPCS deployment (--skip-spcs)"
        return
    fi
    
    log_info "=========================================="
    log_info "Phase 7: SPCS Application"
    log_info "=========================================="
    
    run_sql_script "$REPO_ROOT/scripts/13_spcs_compute.sql"
}

deploy_geospatial() {
    log_info "=========================================="
    log_info "Phase 8: Geospatial Functions"
    log_info "=========================================="
    
    run_sql_script "$REPO_ROOT/scripts/14_geospatial_functions.sql"
}

deploy_rbac() {
    log_info "=========================================="
    log_info "Phase 9: RBAC & Grants"
    log_info "=========================================="
    
    run_sql_script "$REPO_ROOT/scripts/16_rbac_final.sql"
}

load_seed_data() {
    if $SKIP_DATA; then
        log_warn "Skipping seed data loading (--skip-data)"
        return
    fi
    
    log_info "=========================================="
    log_info "Phase 10: Seed Data Loading"
    log_info "=========================================="
    
    # Check if seed data exists
    if [[ -d "$REPO_ROOT/seed_data/small" ]] && [[ -f "$REPO_ROOT/seed_data/small/manifest.json" ]]; then
        log_info "Loading seed data from seed_data/small/"
        python3 "$REPO_ROOT/generators/load_seed_data.py" --source small
    else
        log_warn "Seed data not found. Run generators first or download from releases."
        log_info "Generate data with: python generators/generate_all.py"
    fi
}

run_validation() {
    log_info "=========================================="
    log_info "Phase 11: Validation"
    log_info "=========================================="
    
    run_sql_script "$REPO_ROOT/scripts/17_validation_queries.sql"
    
    # Run Python validation
    if [[ -f "$REPO_ROOT/cli/validate.py" ]]; then
        log_info "Running validation script..."
        python3 "$REPO_ROOT/cli/validate.py" --env "$ENV"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env)
                ENV="$2"
                shift 2
                ;;
            --connection)
                CONNECTION="$2"
                shift 2
                ;;
            --skip-data)
                SKIP_DATA=true
                shift
                ;;
            --skip-spcs)
                SKIP_SPCS=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║           Flux Utility Solutions - Full Deployment               ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║  Environment: $(printf '%-50s' "$ENV")  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    START_TIME=$(date +%s)
    
    check_prerequisites
    load_environment
    
    # Run deployment phases
    deploy_infrastructure
    deploy_core_tables
    deploy_timeseries
    deploy_cortex
    deploy_ml
    deploy_postgres
    deploy_spcs
    deploy_geospatial
    deploy_rbac
    load_seed_data
    run_validation
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    Deployment Complete!                          ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║  Duration: $(printf '%-54s' "${DURATION} seconds")  ║"
    echo "║  Database: $(printf '%-54s' "$DATABASE")  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    log_success "Flux Utility Solutions deployed successfully!"
    log_info "Access Snowsight to explore:"
    log_info "  - Cortex Agent: Projects > Snowflake Intelligence"
    log_info "  - Streamlit Dashboard: Projects > Streamlit"
    log_info "  - SPCS Service: Data Products > Apps"
}

main "$@"
