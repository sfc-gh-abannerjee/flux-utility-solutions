#!/bin/bash
# =============================================================================
# validate_terraform.sh
# Validates Terraform configuration syntax and plan
# =============================================================================
# Usage:
#   ./validate_terraform.sh              # Validate dev environment
#   ./validate_terraform.sh prod         # Validate prod environment
#   ./validate_terraform.sh dev --plan   # Run plan (requires credentials)
# =============================================================================

set -e

ENV=${1:-"dev"}
RUN_PLAN=${2:-""}

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║          Terraform Deployment Validation                         ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  Environment: $(printf '%-54s' "$ENV")  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Check Terraform installed
log_info "Checking prerequisites..."
if command -v terraform &> /dev/null; then
    TF_VERSION=$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4 || terraform version | head -1)
    log_success "Terraform found: $TF_VERSION"
else
    log_error "Terraform not found. Install from: https://terraform.io/downloads"
    exit 1
fi
echo ""

# Step 2: Check required files exist
log_info "Checking required files..."

REQUIRED_FILES=(
    "main.tf"
    "variables.tf"
    "environments/${ENV}.tfvars"
    "modules/database/main.tf"
    "modules/database/variables.tf"
    "modules/warehouse/main.tf"
    "modules/warehouse/variables.tf"
    "modules/cortex/main.tf"
)

ALL_FILES_EXIST=true
for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$SCRIPT_DIR/$file" ]]; then
        log_success "  $file"
    else
        log_error "  $file - MISSING"
        ALL_FILES_EXIST=false
    fi
done

if ! $ALL_FILES_EXIST; then
    log_error "Missing required files. Cannot proceed."
    exit 1
fi
echo ""

# Step 3: Terraform fmt check
log_info "Checking Terraform formatting..."
cd "$SCRIPT_DIR"
if terraform fmt -check -recursive > /dev/null 2>&1; then
    log_success "Formatting is correct"
else
    log_warn "Some files need formatting. Run: terraform fmt -recursive"
fi
echo ""

# Step 4: Terraform init
log_info "Initializing Terraform..."
if terraform init -backend=false > /dev/null 2>&1; then
    log_success "Terraform initialized successfully"
else
    log_error "Terraform init failed"
    terraform init -backend=false
    exit 1
fi
echo ""

# Step 5: Terraform validate
log_info "Validating Terraform configuration..."
if terraform validate > /dev/null 2>&1; then
    log_success "Configuration is valid"
else
    log_error "Configuration has errors:"
    terraform validate
    exit 1
fi
echo ""

# Step 6: Check tfvars file
log_info "Checking environment variables (${ENV}.tfvars)..."
TFVARS_FILE="$SCRIPT_DIR/environments/${ENV}.tfvars"

if [[ -f "$TFVARS_FILE" ]]; then
    # Parse key variables
    DB_NAME=$(grep -E "^database_name" "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' "' || echo "N/A")
    ADMIN_ROLE=$(grep -E "^admin_role" "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' "' || echo "N/A")
    WH_SIZE=$(grep -E "^primary_warehouse_size" "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' "' || echo "N/A")
    SPCS=$(grep -E "^enable_spcs" "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' ' || echo "N/A")
    
    echo "  Database:   $DB_NAME"
    echo "  Admin Role: $ADMIN_ROLE"
    echo "  WH Size:    $WH_SIZE"
    echo "  SPCS:       $SPCS"
    log_success "Environment file parsed"
else
    log_warn "Environment file not found: $TFVARS_FILE"
fi
echo ""

# Step 7: Optional - Run plan
if [[ "$RUN_PLAN" == "--plan" ]]; then
    log_info "Running Terraform plan..."
    echo "NOTE: This requires valid Snowflake credentials"
    echo ""
    
    if terraform plan -var-file="environments/${ENV}.tfvars" -no-color 2>&1; then
        log_success "Plan completed successfully"
    else
        log_warn "Plan failed - check Snowflake credentials"
    fi
else
    log_info "To run a full plan: ./validate_terraform.sh $ENV --plan"
    echo "  (Requires valid Snowflake credentials)"
fi
echo ""

# Summary
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                    Validation Summary                            ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  Status: PASS - Configuration is valid                           ║"
echo "║                                                                  ║"
echo "║  Next steps:                                                     ║"
echo "║    1. Configure Snowflake provider credentials                   ║"
echo "║    2. Run: terraform plan -var-file=environments/${ENV}.tfvars   ║"
echo "║    3. Run: terraform apply -var-file=environments/${ENV}.tfvars  ║"
echo "║    4. Run SQL scripts for tables and Cortex services            ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
