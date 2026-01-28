#!/bin/bash
# ============================================================================
# FLUX UTILITY SOLUTIONS - SEED DATA LOADER
# ============================================================================
# This script uploads bundled CSV seed data to Snowflake and loads it into tables.
# 
# USAGE:
#   ./cli/load_seed_data.sh --database FLUX_OPS --warehouse COMPUTE_WH
#
# PREREQUISITES:
#   - Snowflake CLI installed and configured
#   - Database and schemas already created (run deploy.sh first)
# ============================================================================

set -e

# Default values
DATABASE=""
WAREHOUSE=""
SCHEMA="PRODUCTION"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SEED_DATA_DIR="$REPO_ROOT/seed_data/csv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  FLUX UTILITY SOLUTIONS - SEED DATA LOADER${NC}"
    echo -e "${BLUE}============================================${NC}"
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

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --database|-d)
            DATABASE="$2"
            shift 2
            ;;
        --warehouse|-w)
            WAREHOUSE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 --database DATABASE --warehouse WAREHOUSE"
            echo ""
            echo "Options:"
            echo "  --database, -d   Target database name (required)"
            echo "  --warehouse, -w  Warehouse to use (required)"
            echo "  --help, -h       Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$DATABASE" ]]; then
    print_error "Database name is required. Use --database or -d flag."
    exit 1
fi

if [[ -z "$WAREHOUSE" ]]; then
    print_error "Warehouse name is required. Use --warehouse or -w flag."
    exit 1
fi

print_header

print_info "Configuration:"
echo "  Database:     $DATABASE"
echo "  Warehouse:    $WAREHOUSE"
echo "  Seed Data:    $SEED_DATA_DIR"
echo ""

# Check if seed data files exist
print_step "Checking seed data files..."
REQUIRED_FILES=("substations.csv" "transformers.csv" "meters.csv" "customers.csv")
MISSING_FILES=()

for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$SEED_DATA_DIR/$file" ]]; then
        MISSING_FILES+=("$file")
    fi
done

if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
    print_error "Missing seed data files: ${MISSING_FILES[*]}"
    print_info "Please ensure all CSV files are present in $SEED_DATA_DIR"
    exit 1
fi

print_success "All seed data files found"

# Create stage if it doesn't exist
print_step "Creating seed data stage..."
snow sql -q "USE DATABASE $DATABASE; USE SCHEMA $SCHEMA; CREATE STAGE IF NOT EXISTS SEED_DATA_STAGE DIRECTORY = (ENABLE = TRUE) COMMENT = 'Internal stage for seed data';"

# Create file format
print_step "Creating CSV file format..."
snow sql -q "USE DATABASE $DATABASE; USE SCHEMA $SCHEMA; CREATE OR REPLACE FILE FORMAT CSV_FORMAT TYPE = 'CSV' FIELD_DELIMITER = ',' SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '\"' NULL_IF = ('', 'NULL', 'None') EMPTY_FIELD_AS_NULL = TRUE ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;"

# Upload files to stage
print_step "Uploading seed data files to stage..."

for file in "${REQUIRED_FILES[@]}"; do
    filename="${file%.*}"  # Remove extension
    print_info "Uploading $file..."
    snow stage copy "$SEED_DATA_DIR/$file" "@$DATABASE.$SCHEMA.SEED_DATA_STAGE/$filename/" --overwrite 2>/dev/null || \
        snow sql -q "PUT file://$SEED_DATA_DIR/$file @$DATABASE.$SCHEMA.SEED_DATA_STAGE/$filename/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;"
done

print_success "All files uploaded to stage"

# Load data into tables
print_step "Loading SUBSTATIONS data..."
snow sql -q "
USE DATABASE $DATABASE; USE SCHEMA $SCHEMA; USE WAREHOUSE $WAREHOUSE;
TRUNCATE TABLE IF EXISTS SUBSTATIONS;
COPY INTO SUBSTATIONS (SUBSTATION_ID, SUBSTATION_NAME, LATITUDE, LONGITUDE, CAPACITY_MVA, REGION, VOLTAGE_LEVEL, COMMISSIONED_DATE, OPERATIONAL_STATUS, SUBSTATION_TYPE)
FROM (SELECT \$1, \$2, \$3, \$4, \$5, \$6, \$7, TRY_TO_DATE(\$8, 'YYYY-MM-DD'), \$9, \$10 FROM @SEED_DATA_STAGE/substations/)
FILE_FORMAT = CSV_FORMAT ON_ERROR = 'CONTINUE';
SELECT 'Loaded ' || COUNT(*) || ' substations' FROM SUBSTATIONS;
"

print_step "Loading TRANSFORMER_METADATA data..."
snow sql -q "
USE DATABASE $DATABASE; USE SCHEMA $SCHEMA; USE WAREHOUSE $WAREHOUSE;
TRUNCATE TABLE IF EXISTS TRANSFORMER_METADATA;
COPY INTO TRANSFORMER_METADATA (TRANSFORMER_ID, SUBSTATION_ID, CIRCUIT_ID, LATITUDE, LONGITUDE, RATED_KVA, INSTALL_YEAR, LAST_MAINTENANCE_DATE, CURRENT_LOAD_KVA, PEAK_LOAD_KVA, LOAD_UTILIZATION_PCT, METER_COUNT, HEALTH_SCORE, MANUFACTURER, MODEL_NUMBER)
FROM (SELECT \$1, \$2, \$3, \$4, \$5, \$6, \$7, TRY_TO_DATE(\$8, 'YYYY-MM-DD'), \$9, \$10, \$11, \$12, \$13, \$14, \$15 FROM @SEED_DATA_STAGE/transformers/)
FILE_FORMAT = CSV_FORMAT ON_ERROR = 'CONTINUE';
SELECT 'Loaded ' || COUNT(*) || ' transformers' FROM TRANSFORMER_METADATA;
"

print_step "Loading METER_INFRASTRUCTURE data..."
snow sql -q "
USE DATABASE $DATABASE; USE SCHEMA $SCHEMA; USE WAREHOUSE $WAREHOUSE;
TRUNCATE TABLE IF EXISTS METER_INFRASTRUCTURE;
COPY INTO METER_INFRASTRUCTURE (METER_ID, METER_LATITUDE, METER_LONGITUDE, METER_TYPE, TRANSFORMER_ID, SUBSTATION_ID, CIRCUIT_ID, HEALTH_SCORE, COMMISSIONED_DATE, CITY, ZIP_CODE, CUSTOMER_SEGMENT_ID)
FROM (SELECT \$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, TRY_TO_DATE(\$9, 'YYYY-MM-DD'), \$10, \$11, \$12 FROM @SEED_DATA_STAGE/meters/)
FILE_FORMAT = CSV_FORMAT ON_ERROR = 'CONTINUE';
SELECT 'Loaded ' || COUNT(*) || ' meters' FROM METER_INFRASTRUCTURE;
"

print_step "Loading CUSTOMERS_MASTER_DATA..."
snow sql -q "
USE DATABASE $DATABASE; USE SCHEMA $SCHEMA; USE WAREHOUSE $WAREHOUSE;
TRUNCATE TABLE IF EXISTS CUSTOMERS_MASTER_DATA;
COPY INTO CUSTOMERS_MASTER_DATA (CUSTOMER_ID, FIRST_NAME, LAST_NAME, FULL_NAME, PRIMARY_METER_ID, CUSTOMER_SEGMENT, SERVICE_ADDRESS, SERVICE_COUNTY, CITY, ZIP_CODE, PHONE, EMAIL, ACCOUNT_STATUS, SERVICE_START_DATE)
FROM (SELECT \$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11, \$12, \$13, TRY_TO_DATE(\$14, 'YYYY-MM-DD') FROM @SEED_DATA_STAGE/customers/)
FILE_FORMAT = CSV_FORMAT ON_ERROR = 'CONTINUE';
SELECT 'Loaded ' || COUNT(*) || ' customers' FROM CUSTOMERS_MASTER_DATA;
"

# Generate AMI readings
print_step "Generating AMI readings (7 days of time-series data)..."
snow sql -q "
USE DATABASE $DATABASE; USE SCHEMA $SCHEMA; USE WAREHOUSE $WAREHOUSE;

CREATE OR REPLACE TEMPORARY TABLE AMI_TIMESTAMPS AS
SELECT DATEADD(HOUR, seq4(), DATEADD(DAY, -7, CURRENT_TIMESTAMP())) AS reading_time
FROM TABLE(GENERATOR(ROWCOUNT => 168));

INSERT INTO AMI_READINGS (METER_ID, READING_TIMESTAMP, READING_VALUE_KWH, READING_TYPE, QUALITY_FLAG)
SELECT 
    m.METER_ID,
    t.reading_time,
    ROUND(
        CASE 
            WHEN m.CUSTOMER_SEGMENT_ID = 'RESIDENTIAL' THEN 0.8
            WHEN m.CUSTOMER_SEGMENT_ID = 'COMMERCIAL' THEN 2.5
            WHEN m.CUSTOMER_SEGMENT_ID = 'INDUSTRIAL' THEN 8.0
            ELSE 1.0
        END
        * CASE 
            WHEN HOUR(t.reading_time) BETWEEN 6 AND 9 THEN 1.3
            WHEN HOUR(t.reading_time) BETWEEN 17 AND 21 THEN 1.5
            WHEN HOUR(t.reading_time) BETWEEN 0 AND 5 THEN 0.4
            ELSE 1.0
        END
        * (0.8 + RANDOM() * 0.4)
    , 3),
    'INTERVAL',
    CASE WHEN RANDOM() < 0.98 THEN 'VALID' ELSE 'ESTIMATED' END
FROM METER_INFRASTRUCTURE m
CROSS JOIN AMI_TIMESTAMPS t
WHERE m.METER_ID IS NOT NULL;

SELECT 'Generated ' || COUNT(*) || ' AMI readings' FROM AMI_READINGS;
"

# Final summary
print_step "Loading complete! Final row counts:"
snow sql -q "
USE DATABASE $DATABASE; USE SCHEMA $SCHEMA;
SELECT 'SUBSTATIONS' AS table_name, COUNT(*) AS row_count FROM SUBSTATIONS
UNION ALL SELECT 'TRANSFORMER_METADATA', COUNT(*) FROM TRANSFORMER_METADATA
UNION ALL SELECT 'METER_INFRASTRUCTURE', COUNT(*) FROM METER_INFRASTRUCTURE
UNION ALL SELECT 'CUSTOMERS_MASTER_DATA', COUNT(*) FROM CUSTOMERS_MASTER_DATA
UNION ALL SELECT 'AMI_READINGS', COUNT(*) FROM AMI_READINGS;
"

echo ""
print_success "Seed data loading complete!"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Run validation: snow sql -f scripts/99_validate_deployment.sql -D \"database='$DATABASE'\""
echo "  2. Launch Streamlit app: streamlit run streamlit/Home.py"
