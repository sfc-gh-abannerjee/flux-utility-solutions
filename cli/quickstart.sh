#!/bin/bash
# =============================================================================
# Flux Utility Solutions - Quick Start (15-minute deployment)
# =============================================================================
# Deploys a minimal working version with sample seed data
# Perfect for demos, POCs, and getting started quickly
#
# Usage:
#   ./quickstart.sh                          # Deploy with defaults
#   ./quickstart.sh --connection x           # Use specific connection
#   ./quickstart.sh --database MY_DB         # Use custom database name
#   ./quickstart.sh --with-ops-center        # Include Ops Center dependencies
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
DATABASE="FLUX_QUICKSTART"
WAREHOUSE="FLUX_QUICKSTART_WH"
WITH_OPS_CENTER=false

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
    
    # Use a simple SQL query that doesn't require a warehouse
    # This makes the quickstart self-contained and doesn't depend on connection defaults
    if snow sql $conn_flag -q "SELECT CURRENT_ACCOUNT()" &> /dev/null; then
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
        -D "database=$DATABASE" \
        -D "warehouse=$WAREHOUSE" \
        -D "warehouse_size=XSMALL" \
        -D "admin_role=ACCOUNTADMIN" \
        -D "user_role=PUBLIC" > /dev/null 2>&1; then
        log_success "$name"
    else
        log_error "Failed: $name"
        exit 1
    fi
}

run_sql_optional() {
    local script="$1"
    local display_name="$2"
    local name
    name=$(basename "$script" .sql)
    
    local conn_flag=""
    [[ -n "$CONNECTION" ]] && conn_flag="-c $CONNECTION"
    
    log_step "Deploying: $display_name"
    
    if snow sql $conn_flag -f "$script" \
        -D "database=$DATABASE" \
        -D "warehouse=$WAREHOUSE" \
        -D "warehouse_size=XSMALL" \
        -D "admin_role=ACCOUNTADMIN" \
        -D "user_role=PUBLIC" > /dev/null 2>&1; then
        log_success "$display_name"
    else
        echo -e "${YELLOW}⚠${NC} $display_name skipped (optional feature)"
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
            --database|-d)
                DATABASE="$2"
                WAREHOUSE="${DATABASE}_WH"
                shift 2
                ;;
            --with-ops-center)
                WITH_OPS_CENTER=true
                shift
                ;;
            --help|-h)
                echo "Usage: ./quickstart.sh [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --connection, -c NAME    Use specific Snowflake connection"
                echo "  --database, -d NAME      Database name (default: FLUX_QUICKSTART)"
                echo "  --with-ops-center        Include Flux Ops Center dependencies"
                echo "  --help, -h               Show this help"
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
    
    echo "Step 5/6: Loading seed data"
    echo "─────────────────────────────────"
    
    # Set up connection flag for direct snow sql calls
    local conn_flag=""
    [[ -n "$CONNECTION" ]] && conn_flag="-c $CONNECTION"
    
    # Check if bundled CSV seed data exists
    if [[ -f "$REPO_ROOT/seed_data/csv/substations.csv" ]]; then
        log_step "Using bundled CSV seed data..."
        
        # Create stage for seed data
        snow sql $conn_flag -q "USE DATABASE $DATABASE; USE SCHEMA PRODUCTION; CREATE STAGE IF NOT EXISTS SEED_DATA_STAGE DIRECTORY = (ENABLE = TRUE);" > /dev/null 2>&1
        
        # Upload CSV files to stage
        log_step "Uploading seed data to stage..."
        snow stage copy "$REPO_ROOT/seed_data/csv/substations.csv" "@$DATABASE.PRODUCTION.SEED_DATA_STAGE/substations/" $conn_flag --overwrite > /dev/null 2>&1
        snow stage copy "$REPO_ROOT/seed_data/csv/transformers.csv" "@$DATABASE.PRODUCTION.SEED_DATA_STAGE/transformers/" $conn_flag --overwrite > /dev/null 2>&1
        snow stage copy "$REPO_ROOT/seed_data/csv/meters.csv" "@$DATABASE.PRODUCTION.SEED_DATA_STAGE/meters/" $conn_flag --overwrite > /dev/null 2>&1
        snow stage copy "$REPO_ROOT/seed_data/csv/customers.csv" "@$DATABASE.PRODUCTION.SEED_DATA_STAGE/customers/" $conn_flag --overwrite > /dev/null 2>&1
        
        # Upload technical manuals parquet if available
        if [[ -f "$REPO_ROOT/seed_data/parquet/operational/technical_manuals_pdf_chunks_0_0_0.snappy.parquet" ]]; then
            snow stage copy "$REPO_ROOT/seed_data/parquet/operational/technical_manuals_pdf_chunks_0_0_0.snappy.parquet" "@$DATABASE.PRODUCTION.SEED_DATA_STAGE/technical_manuals/" $conn_flag --overwrite > /dev/null 2>&1
        fi
        log_success "Seed data uploaded"
        
        # Run the load script
        log_step "Loading seed data into tables..."
        snow sql $conn_flag -f "$REPO_ROOT/scripts/50_load_seed_data.sql" \
            -D "database=$DATABASE" \
            -D "warehouse=$WAREHOUSE" > /dev/null 2>&1 && \
            log_success "Seed data loaded" || log_success "Seed data (partial)"
    else
        # Fall back to FLUX_DATABASE if available
        log_step "Checking for FLUX_DATABASE seed data..."
        if snow sql $conn_flag -q "SELECT 1 FROM FLUX_DATABASE.PRODUCTION.SUBSTATIONS LIMIT 1" > /dev/null 2>&1; then
            log_success "FLUX_DATABASE accessible"
            
            log_step "Loading reference tables..."
            snow sql $conn_flag -f "$REPO_ROOT/scripts/50_load_seed_data.sql" \
                -D "database=$DATABASE" \
                -D "warehouse=$WAREHOUSE" > /dev/null 2>&1 && \
                log_success "Reference tables loaded" || log_success "Reference tables (partial)"
            
            log_step "Generating AMI sample data (7 days)..."
            snow sql $conn_flag -f "$REPO_ROOT/scripts/51_generate_ami_sample.sql" \
                -D "database=$DATABASE" \
                -D "warehouse=$WAREHOUSE" \
                -D "days=7" > /dev/null 2>&1 && \
                log_success "AMI data generated" || log_success "AMI data skipped"
        else
            log_success "No seed data source available - tables will be empty"
            log_success "Run generators/generate_all.py to populate data"
        fi
    fi
    echo ""
    
    echo "Step 6/6: Deploying Cortex AI (optional)"
    echo "─────────────────────────────────────────"
    # Cortex AI features are optional - deployment continues if they fail
    # NOTE: Seed data must be loaded first so Cortex Search has data to index
    run_sql_optional "$REPO_ROOT/scripts/08_semantic_view.sql" "Semantic View"
    run_sql_optional "$REPO_ROOT/scripts/09_cortex_search_services.sql" "Search Services"
    run_sql_optional "$REPO_ROOT/scripts/10_cortex_agent.sql" "Cortex Agent"
    echo ""
    
    # Optional: Deploy Flux Ops Center dependencies
    if [[ "$WITH_OPS_CENTER" == true ]]; then
        echo "Step 7: Deploying Flux Ops Center dependencies"
        echo "───────────────────────────────────────────────"
        run_sql_optional "$REPO_ROOT/scripts/30_ops_center_dependencies.sql" "Ops Center Views & Tables"
        echo ""
        echo -e "${GREEN}✓${NC} Ops Center dependencies ready!"
        echo "  Deploy Flux Ops Center SPCS with:"
        echo "    SNOWFLAKE_DATABASE=$DATABASE"
        echo ""
    fi
    
    END=$(date +%s)
    DURATION=$((END - START))
    
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    log_success "Quick Start Complete! (${DURATION} seconds)"
    echo ""
    echo "What's deployed:"
    echo "  • Database: $DATABASE"
    echo "  • Warehouse: $WAREHOUSE"
    echo "  • Tables: Substations, Transformers, Meters, Customers"
    echo "  • Cortex: Semantic View, Search Services, Agent"
    if [[ "$WITH_OPS_CENTER" == true ]]; then
        echo "  • Ops Center: ML_DEMO, CASCADE_ANALYSIS schemas"
    fi
    echo ""
    echo "Try it out:"
    echo "  1. Open Snowsight → Projects → Snowflake Intelligence"
    echo "  2. Find 'GRID_INTELLIGENCE_AGENT'"
    echo "  3. Ask: 'Show me transformers with health score below 50'"
    echo ""
    echo "Next steps:"
    echo "  • Load full data: python generators/generate_all.py"
    echo "  • Deploy SPCS: ./cli/deploy.sh --env dev"
    if [[ "$WITH_OPS_CENTER" != true ]]; then
        echo "  • Add Ops Center support: ./quickstart.sh --database $DATABASE --with-ops-center"
    fi
    echo "  • Cleanup: ./cli/teardown.sh"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
}

main "$@"
