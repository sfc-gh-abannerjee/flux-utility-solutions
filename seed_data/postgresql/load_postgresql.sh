#!/bin/bash
# ============================================================================
# FLUX UTILITY SOLUTIONS - POSTGRESQL SEED DATA LOADER
# ============================================================================
# This script sets up PostgreSQL schema and loads seed data.
#
# USAGE:
#   ./seed_data/postgresql/load_postgresql.sh \
#       --host localhost \
#       --port 5432 \
#       --database flux_ops \
#       --user postgres
#
# PREREQUISITES:
#   - PostgreSQL client (psql) installed
#   - Target database created
#   - CSV files present in seed_data/csv/
# ============================================================================

set -e

# Default values
PG_HOST="localhost"
PG_PORT="5432"
PG_DATABASE="flux_ops"
PG_USER="postgres"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}  FLUX OPS - POSTGRESQL SEED DATA LOADER${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --host|-h)
            PG_HOST="$2"
            shift 2
            ;;
        --port|-p)
            PG_PORT="$2"
            shift 2
            ;;
        --database|-d)
            PG_DATABASE="$2"
            shift 2
            ;;
        --user|-u)
            PG_USER="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --host, -h      PostgreSQL host (default: localhost)"
            echo "  --port, -p      PostgreSQL port (default: 5432)"
            echo "  --database, -d  Database name (default: flux_ops)"
            echo "  --user, -u      PostgreSQL user (default: postgres)"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_header

print_info "Configuration:"
echo "  Host:     $PG_HOST"
echo "  Port:     $PG_PORT"
echo "  Database: $PG_DATABASE"
echo "  User:     $PG_USER"
echo "  Repo:     $REPO_ROOT"
echo ""

# Check prerequisites
print_step "Checking prerequisites..."

if ! command -v psql &> /dev/null; then
    print_error "psql command not found. Please install PostgreSQL client."
    exit 1
fi

# Check CSV files
CSV_DIR="$REPO_ROOT/seed_data/csv"
REQUIRED_FILES=("substations.csv" "transformers.csv" "meters.csv" "customers.csv")
MISSING_FILES=()

for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$CSV_DIR/$file" ]]; then
        MISSING_FILES+=("$file")
    fi
done

if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
    print_error "Missing CSV files: ${MISSING_FILES[*]}"
    exit 1
fi

print_success "All prerequisites met"

# Create database if it doesn't exist
print_step "Creating database if needed..."
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -tc \
    "SELECT 1 FROM pg_database WHERE datname = '$PG_DATABASE'" | grep -q 1 || \
    psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -c "CREATE DATABASE $PG_DATABASE"

# Run schema creation
print_step "Creating schema..."
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
    -f "$SCRIPT_DIR/01_schema.sql"

# Load seed data using COPY with absolute paths
print_step "Loading substations..."
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" <<EOF
SET search_path TO production;
TRUNCATE TABLE substations CASCADE;
\copy substations(substation_id,substation_name,latitude,longitude,capacity_mva,region,voltage_level,commissioned_date,operational_status,substation_type) FROM '$CSV_DIR/substations.csv' WITH (FORMAT CSV, HEADER TRUE, NULL '');
SELECT 'Loaded ' || COUNT(*) || ' substations' FROM substations;
EOF

print_step "Loading transformers..."
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" <<EOF
SET search_path TO production;
TRUNCATE TABLE transformer_metadata CASCADE;
\copy transformer_metadata(transformer_id,substation_id,circuit_id,latitude,longitude,rated_kva,install_year,last_maintenance_date,current_load_kva,peak_load_kva,load_utilization_pct,meter_count,health_score,manufacturer,model_number) FROM '$CSV_DIR/transformers.csv' WITH (FORMAT CSV, HEADER TRUE, NULL '');
SELECT 'Loaded ' || COUNT(*) || ' transformers' FROM transformer_metadata;
EOF

print_step "Loading meters..."
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" <<EOF
SET search_path TO production;
TRUNCATE TABLE meter_infrastructure CASCADE;
\copy meter_infrastructure(meter_id,meter_latitude,meter_longitude,meter_type,transformer_id,substation_id,circuit_id,health_score,commissioned_date,city,zip_code,customer_segment_id) FROM '$CSV_DIR/meters.csv' WITH (FORMAT CSV, HEADER TRUE, NULL '');
SELECT 'Loaded ' || COUNT(*) || ' meters' FROM meter_infrastructure;
EOF

print_step "Loading customers..."
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" <<EOF
SET search_path TO production;
TRUNCATE TABLE customers_master_data CASCADE;
\copy customers_master_data(customer_id,first_name,last_name,full_name,primary_meter_id,customer_segment,service_address,service_county,city,zip_code,phone,email,account_status,service_start_date) FROM '$CSV_DIR/customers.csv' WITH (FORMAT CSV, HEADER TRUE, NULL '');
SELECT 'Loaded ' || COUNT(*) || ' customers' FROM customers_master_data;
EOF

print_step "Generating AMI readings..."
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" <<'EOF'
SET search_path TO production;
TRUNCATE TABLE ami_readings;

WITH timestamps AS (
    SELECT generate_series(
        NOW() - INTERVAL '7 days',
        NOW(),
        INTERVAL '1 hour'
    ) AS reading_time
)
INSERT INTO ami_readings (meter_id, reading_timestamp, reading_value_kwh, reading_type, quality_flag)
SELECT 
    m.meter_id,
    t.reading_time,
    ROUND(
        (CASE 
            WHEN m.customer_segment_id = 'RESIDENTIAL' THEN 0.8
            WHEN m.customer_segment_id = 'COMMERCIAL' THEN 2.5
            WHEN m.customer_segment_id = 'INDUSTRIAL' THEN 8.0
            ELSE 1.0
        END
        * CASE 
            WHEN EXTRACT(HOUR FROM t.reading_time) BETWEEN 6 AND 9 THEN 1.3
            WHEN EXTRACT(HOUR FROM t.reading_time) BETWEEN 17 AND 21 THEN 1.5
            WHEN EXTRACT(HOUR FROM t.reading_time) BETWEEN 0 AND 5 THEN 0.4
            ELSE 1.0
        END
        * (0.8 + RANDOM() * 0.4))::NUMERIC
    , 3),
    'INTERVAL',
    CASE WHEN RANDOM() < 0.98 THEN 'VALID' ELSE 'ESTIMATED' END
FROM meter_infrastructure m
CROSS JOIN timestamps t;

SELECT 'Generated ' || COUNT(*) || ' AMI readings' FROM ami_readings;
EOF

# Print summary
print_step "Final summary..."
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" <<EOF
SET search_path TO production;
SELECT 'substations' AS table_name, COUNT(*) AS row_count FROM substations
UNION ALL SELECT 'transformer_metadata', COUNT(*) FROM transformer_metadata
UNION ALL SELECT 'meter_infrastructure', COUNT(*) FROM meter_infrastructure
UNION ALL SELECT 'customers_master_data', COUNT(*) FROM customers_master_data
UNION ALL SELECT 'ami_readings', COUNT(*) FROM ami_readings
ORDER BY table_name;
EOF

echo ""
print_success "PostgreSQL seed data loading complete!"
