#!/bin/bash
# ============================================================================
# FLUX UTILITY SOLUTIONS - Full Seed Data Upload Script
# ============================================================================
# Uploads all Parquet files from seed_data/full/ to Snowflake stage
# 
# Usage:
#   ./cli/upload_seed_data.sh --database FLUX_OPS --warehouse COMPUTE_WH
#   ./cli/upload_seed_data.sh -d FLUX_OPS -w COMPUTE_WH
# ============================================================================

set -e

# Default values
DATABASE=""
WAREHOUSE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SEED_DATA_DIR="$REPO_ROOT/seed_data/full"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--database)
            DATABASE="$2"
            shift 2
            ;;
        -w|--warehouse)
            WAREHOUSE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --database DATABASE --warehouse WAREHOUSE"
            echo ""
            echo "Options:"
            echo "  -d, --database   Target database name (required)"
            echo "  -w, --warehouse  Warehouse to use (required)"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$DATABASE" ]]; then
    echo -e "${RED}Error: --database is required${NC}"
    exit 1
fi

if [[ -z "$WAREHOUSE" ]]; then
    echo -e "${RED}Error: --warehouse is required${NC}"
    exit 1
fi

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  FLUX Seed Data Upload                    ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "Database:  ${GREEN}$DATABASE${NC}"
echo -e "Warehouse: ${GREEN}$WAREHOUSE${NC}"
echo -e "Data Dir:  ${GREEN}$SEED_DATA_DIR${NC}"
echo ""

# Check if seed data directory exists
if [[ ! -d "$SEED_DATA_DIR" ]]; then
    echo -e "${RED}Error: Seed data directory not found: $SEED_DATA_DIR${NC}"
    exit 1
fi

# Create the stage
echo -e "${YELLOW}>>> Creating stage FULL_SEED_DATA_STAGE...${NC}"
snow sql -q "USE WAREHOUSE $WAREHOUSE; USE DATABASE $DATABASE; USE SCHEMA PRODUCTION; CREATE STAGE IF NOT EXISTS FULL_SEED_DATA_STAGE FILE_FORMAT = (TYPE = 'PARQUET') DIRECTORY = (ENABLE = TRUE) COMMENT = 'Stage for full production seed data';"

# Tables to upload
TABLES=("substations" "circuits" "transformers" "meters" "customers" "power_lines" "work_orders" "outage_events" "weather_events")

# Upload each table's parquet files
for TABLE in "${TABLES[@]}"; do
    TABLE_DIR="$SEED_DATA_DIR/$TABLE"
    
    if [[ -d "$TABLE_DIR" ]]; then
        FILE_COUNT=$(find "$TABLE_DIR" -name "*.parquet" | wc -l | tr -d ' ')
        
        if [[ $FILE_COUNT -gt 0 ]]; then
            echo -e "${YELLOW}>>> Uploading $TABLE ($FILE_COUNT files)...${NC}"
            
            # Upload all parquet files in the directory
            for PARQUET_FILE in "$TABLE_DIR"/*.parquet; do
                if [[ -f "$PARQUET_FILE" ]]; then
                    FILENAME=$(basename "$PARQUET_FILE")
                    snow stage copy "$PARQUET_FILE" "@$DATABASE.PRODUCTION.FULL_SEED_DATA_STAGE/$TABLE/" --overwrite 2>/dev/null || \
                    snow sql -q "USE DATABASE $DATABASE; USE SCHEMA PRODUCTION; PUT 'file://$PARQUET_FILE' @FULL_SEED_DATA_STAGE/$TABLE/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;"
                fi
            done
            
            echo -e "${GREEN}   Uploaded $TABLE${NC}"
        else
            echo -e "${YELLOW}   Skipping $TABLE (no parquet files)${NC}"
        fi
    else
        echo -e "${YELLOW}   Skipping $TABLE (directory not found)${NC}"
    fi
done

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}  Upload Complete!                         ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "Next step: Run the loading script:"
echo -e "  ${YELLOW}snow sql -f scripts/51_load_full_seed_data.sql \\${NC}"
echo -e "  ${YELLOW}  -D \"database='$DATABASE'\" \\${NC}"
echo -e "  ${YELLOW}  -D \"warehouse='$WAREHOUSE'\"${NC}"
echo ""

# List uploaded files
echo -e "${YELLOW}>>> Verifying uploaded files...${NC}"
snow sql -q "USE DATABASE $DATABASE; USE SCHEMA PRODUCTION; LIST @FULL_SEED_DATA_STAGE;"
