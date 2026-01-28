#!/bin/bash
# =============================================================================
# validate_sql_deployment.sh
# Master validation script for SQL Scripts deployment path
# =============================================================================
# Usage: ./scripts/validate/validate_sql_deployment.sh <database_name>
# Example: ./scripts/validate/validate_sql_deployment.sh FLUX_PROD
# =============================================================================

set -e

DATABASE=${1:-"FLUX_PROD"}

echo "=========================================="
echo "Flux Utility Solutions - SQL Path Validation"
echo "Database: $DATABASE"
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to run validation script
run_validation() {
    local script=$1
    local step=$2
    echo ">>> Running Step $step Validation..."
    snow sql -f "$SCRIPT_DIR/${script}" -D "database='$DATABASE'" --format json 2>/dev/null || {
        echo "WARN: Step $step validation had issues"
    }
    echo ""
}

echo "Step 1: Database Infrastructure"
run_validation "01_validate_infrastructure.sql" "1"

echo "Step 2: Data Stages"
run_validation "02_validate_stages.sql" "2"

echo "Step 3: Grid Foundation (Substations/Transformers)"
run_validation "03_validate_grid_foundation.sql" "3"

echo "Step 4: Meter Infrastructure"
run_validation "04_validate_meters.sql" "4"

echo "Step 5: Customer Master Data"
run_validation "05_validate_customers.sql" "5"

echo "Step 6: AMI Readings Pipeline"
run_validation "06_validate_ami_pipeline.sql" "6"

echo "Step 7: Aggregation Tables"
run_validation "07_validate_aggregations.sql" "7"

echo "Step 8: Cortex Services"
run_validation "08_validate_cortex.sql" "8"

echo "=========================================="
echo "Full Deployment Validation"
echo "=========================================="
snow sql -f "$SCRIPT_DIR/../99_validate_deployment.sql" -D "database='$DATABASE'" 2>/dev/null

echo ""
echo "=========================================="
echo "Validation Complete!"
echo "Review results above for any FAIL or WARN"
echo "=========================================="
