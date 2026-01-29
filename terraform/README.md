# Flux Utility Solutions - Terraform Configuration

Infrastructure as Code (IaC) for deploying Flux to Snowflake.

## Important: Provider Version

This configuration requires **Snowflake Terraform Provider >= 0.92**.

The Snowflake provider underwent a major grant resources redesign in 2024. The old grant resources (`snowflake_database_grant`, `snowflake_warehouse_grant`, `snowflake_role_grants`, etc.) were **removed on June 26, 2024**. This configuration uses the new grant resources:

| Old Resource (Removed) | New Resource |
|------------------------|--------------|
| `snowflake_database_grant` | `snowflake_grant_privileges_to_account_role` |
| `snowflake_warehouse_grant` | `snowflake_grant_privileges_to_account_role` |
| `snowflake_schema_grant` | `snowflake_grant_privileges_to_account_role` |
| `snowflake_table_grant` | `snowflake_grant_privileges_to_account_role` |
| `snowflake_role_grants` | `snowflake_grant_account_role` |

For migration guidance, see: [Snowflake Provider Grant Redesign](https://registry.terraform.io/providers/snowflakedb/snowflake/latest/docs/guides/grants_redesign_design_decisions)

## Directory Structure

```
terraform/
├── README.md
├── main.tf              # Root module
├── variables.tf         # Input variables
├── environments/        # Environment-specific configs
│   ├── dev.tfvars
│   ├── staging.tfvars
│   └── prod.tfvars
├── validate_terraform.sh # Validation script
└── modules/
    ├── database/        # Database, schemas, and roles
    ├── warehouse/       # Warehouse configuration
    └── cortex/          # Cortex infrastructure (SPCS stages, compute pools)
```

## Prerequisites

1. **Terraform >= 1.0**
2. **Snowflake Terraform Provider >= 0.92**

```bash
# Install Terraform (macOS)
brew install terraform

# Or download from https://terraform.io/downloads
```

### Snowflake Authentication

Configure one of these authentication methods:

**Option 1: Key Pair Authentication (Recommended)**
```bash
export SNOWFLAKE_USER="your_user"
export SNOWFLAKE_ACCOUNT="your_account"  # e.g., "xy12345.us-west-2"
export SNOWFLAKE_PRIVATE_KEY_PATH="/path/to/rsa_key.p8"
```

**Option 2: Password Authentication**
```bash
export SNOWFLAKE_USER="your_user"
export SNOWFLAKE_ACCOUNT="your_account"
export SNOWFLAKE_PASSWORD="your_password"
```

**Option 3: Browser-based SSO**
```bash
export SNOWFLAKE_USER="your_user"
export SNOWFLAKE_ACCOUNT="your_account"
export SNOWFLAKE_AUTHENTICATOR="externalbrowser"
```

## Quick Start

```bash
# Initialize
terraform init

# Plan (dev environment)
terraform plan -var-file="environments/dev.tfvars"

# Apply
terraform apply -var-file="environments/dev.tfvars"

# Destroy (careful!)
terraform destroy -var-file="environments/dev.tfvars"
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `environment` | dev, staging, prod |
| `database_name` | Target database name |
| `warehouse_size` | XS, S, M, L, XL |
| `admin_role` | Admin role name |
| `user_role` | User role name |

## Module Usage

### Database Module

```hcl
module "flux_database" {
  source = "./modules/database"
  
  database_name = "FLUX_PROD"
  admin_role    = "FLUX_PROD_ADMIN"
  user_role     = "FLUX_PROD_USER"
}
```

### Warehouse Module

```hcl
module "flux_warehouses" {
  source = "./modules/warehouse"
  
  warehouse_prefix = "FLUX_PROD"
  primary_size     = "MEDIUM"
  admin_role       = module.flux_database.admin_role
}
```

### Cortex Module

```hcl
module "flux_cortex" {
  source = "./modules/cortex"
  
  database_name  = module.flux_database.database_name
  semantic_model = file("../models/utility_semantic_model.yaml")
}
```

## State Management

For production, use remote state:

```hcl
terraform {
  backend "s3" {
    bucket = "flux-terraform-state"
    key    = "prod/terraform.tfstate"
    region = "us-west-2"
  }
}
```

## Limitations

The Snowflake Terraform provider doesn't yet support:
- Cortex Search Services (use SQL scripts)
- Cortex Agents (use SQL scripts)
- Semantic Views (use SQL scripts)

Use Terraform for infrastructure (databases, warehouses, roles) and SQL scripts for Cortex components.
