# Flux Utility Solutions - Terraform Configuration

Infrastructure as Code (IaC) for deploying Flux to Snowflake.

## Directory Structure

```
terraform/
├── README.md
├── main.tf              # Root module
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── providers.tf         # Provider configuration
├── environments/        # Environment-specific configs
│   ├── dev.tfvars
│   ├── staging.tfvars
│   └── prod.tfvars
└── modules/
    ├── database/        # Database and schema module
    ├── warehouse/       # Warehouse module
    └── cortex/          # Cortex services module
```

## Prerequisites

1. **Terraform >= 1.0**
2. **Snowflake Terraform Provider**

```bash
# Install Terraform
brew install terraform

# Configure Snowflake credentials
export SNOWFLAKE_USER="your_user"
export SNOWFLAKE_ACCOUNT="your_account"
export SNOWFLAKE_PRIVATE_KEY_PATH="/path/to/rsa_key.p8"
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
