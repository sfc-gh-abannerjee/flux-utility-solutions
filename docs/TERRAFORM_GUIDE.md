# Terraform Deployment Guide

> Infrastructure as Code for Flux Utility Solutions

This guide covers deploying Flux infrastructure using Terraform with the Snowflake provider.

## Prerequisites

### 1. Install Terraform
```bash
# macOS
brew install terraform

# Linux
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install terraform

# Verify
terraform version
```

### 2. Snowflake Authentication
```bash
# Option 1: Environment variables
export SNOWFLAKE_ACCOUNT="your_account"
export SNOWFLAKE_USER="your_user"
export SNOWFLAKE_PASSWORD="your_password"
export SNOWFLAKE_ROLE="ACCOUNTADMIN"

# Option 2: Snowflake config file (~/.snowflake/config)
[default]
account = your_account
user = your_user
password = your_password
role = ACCOUNTADMIN
warehouse = COMPUTE_WH
```

### 3. Clone Repository
```bash
git clone https://github.com/Snowflake-Labs/flux-utility-solutions.git
cd flux-utility-solutions/terraform
```

---

## Module Structure

```
terraform/
├── main.tf                      # Root configuration
├── variables.tf                 # Input variables
├── outputs.tf                   # Output values
├── environments/
│   ├── dev.tfvars               # Development settings
│   ├── staging.tfvars           # Staging settings
│   └── prod.tfvars              # Production settings
└── modules/
    ├── database/                # Database, schemas, roles
    │   ├── main.tf
    │   └── variables.tf
    ├── warehouse/               # Compute warehouses
    │   ├── main.tf
    │   └── variables.tf
    ├── tables/                  # Data tables
    │   ├── main.tf
    │   └── variables.tf
    ├── semantic_view/           # Cortex Analyst semantic views
    │   ├── main.tf
    │   └── variables.tf
    ├── cortex_search/           # Cortex Search services
    │   ├── main.tf
    │   └── variables.tf
    ├── cortex_agent/            # Cortex AI Agents
    │   ├── main.tf
    │   └── variables.tf
    ├── postgres/                # PostgreSQL managed service
    │   ├── main.tf
    │   └── variables.tf
    └── spcs/                    # Snowpark Container Services
        ├── main.tf
        └── variables.tf
```

---

## Quick Start

### 1. Initialize Terraform
```bash
cd terraform
terraform init
```

Expected output:
```
Initializing modules...
Initializing provider plugins...
- Finding snowflake-labs/snowflake versions matching "~> 0.87"...
- Installing snowflake-labs/snowflake v0.87.x...

Terraform has been successfully initialized!
```

### 2. Create Environment File
```bash
# Copy template
cp environments/dev.tfvars.example environments/dev.tfvars

# Edit with your values
vim environments/dev.tfvars
```

Example `dev.tfvars`:
```hcl
# Environment
environment = "dev"

# Database
database_name = "FLUX_DEV"

# Roles
admin_role    = "FLUX_DEV_ADMIN"
user_role     = "FLUX_DEV_USER"
terraform_role = "ACCOUNTADMIN"

# Warehouses
warehouse_prefix       = "FLUX_DEV"
primary_warehouse_size = "XSMALL"
large_warehouse_size   = "SMALL"
cortex_warehouse_size  = "SMALL"

# SPCS
enable_spcs        = true
compute_pool_name  = "FLUX_DEV_POOL"

# PostgreSQL (optional)
enable_postgres = false
```

### 3. Plan Deployment
```bash
terraform plan -var-file="environments/dev.tfvars"
```

Review the plan output carefully. It shows:
- Resources to be created (+)
- Resources to be modified (~)
- Resources to be destroyed (-)

### 4. Apply Deployment
```bash
terraform apply -var-file="environments/dev.tfvars"
```

Type `yes` when prompted to confirm.

---

## Module Details

### Database Module
Creates the foundational database, schemas, and roles.

```hcl
module "database" {
  source = "./modules/database"
  
  database_name = var.database_name
  admin_role    = var.admin_role
  user_role     = var.user_role
  
  schemas = [
    "PRODUCTION",      # Core data
    "APPLICATIONS",    # Cortex services, SPCS
    "SECRETS"          # Credentials
  ]
}
```

**Resources Created:**
- Database
- 3 Schemas
- Admin and User roles
- Role hierarchy grants
- Future grants on tables

### Warehouse Module
Creates compute warehouses for different workloads.

```hcl
module "warehouses" {
  source = "./modules/warehouse"
  
  warehouse_prefix = var.warehouse_prefix
  
  warehouses = {
    primary = {
      size              = "XSMALL"
      auto_suspend      = 60
      auto_resume       = true
    }
    large = {
      size              = "MEDIUM"
      auto_suspend      = 120
      enable_query_acceleration = true
    }
    cortex = {
      size              = "SMALL"
      auto_suspend      = 60
    }
  }
}
```

### Tables Module
Creates dimension and fact tables for the data model.

```hcl
module "tables" {
  source = "./modules/tables"
  
  database_name = module.database.database_name
  schema_name   = "PRODUCTION"
  
  create_streaming_tables = true
  enable_clustering       = true
}
```

**Tables Created:**
- SUBSTATIONS (98 rows)
- TRANSFORMERS (91K rows)
- METERS (597K rows)
- CUSTOMERS (686K rows)
- AMI_READINGS (7.1B rows at scale)
- TRANSFORMER_HOURLY_METRICS (211M rows)
- OUTAGE_EVENTS
- STREAMING_AMI_READINGS

### Semantic View Module
Creates Cortex Analyst semantic views from YAML models.

```hcl
module "semantic_view" {
  source = "./modules/semantic_view"
  
  database_name = module.database.database_name
  
  create_ami_semantic_view  = true
  create_grid_semantic_view = true
  
  grant_to_roles = [var.user_role]
}
```

**Prerequisites:**
1. Upload YAML files to stage:
```bash
snow stage put models/domain_views/ami_domain.yaml @SEMANTIC_MODELS
snow stage put models/domain_views/grid_topology_domain.yaml @SEMANTIC_MODELS
```

### Cortex Search Module
Creates vector search services for natural language queries.

```hcl
module "cortex_search" {
  source = "./modules/cortex_search"
  
  database_name = module.database.database_name
  warehouse     = module.warehouses.primary_warehouse_name
  
  create_customer_search = true
  create_asset_search    = true
  
  target_lag = "1 hour"
}
```

**Services Created:**
- CUSTOMER_SEARCH_SERVICE - Find customers by description
- ASSET_SEARCH_SERVICE - Find transformers/substations

### Cortex Agent Module
Creates AI agents with the 4-layer instruction pattern.

```hcl
module "cortex_agent" {
  source = "./modules/cortex_agent"
  
  database_name = module.database.database_name
  warehouse     = module.warehouses.cortex_warehouse_name
  model         = "claude-3-5-sonnet"
  
  create_grid_analyst     = true
  create_customer_agent   = true
  create_engineering_agent = true
  
  # Tool configuration
  enable_analyst_tool = true
  enable_search_tool  = true
  enable_sql_tool     = true
  
  semantic_view_name      = "AMI_ANALYTICS_SEMANTIC"
  customer_search_service = module.cortex_search.search_services.customer
}
```

**Agents Created:**
- FLUX_GRID_ANALYST - Grid operations analysis
- FLUX_CUSTOMER_AGENT - Customer service support
- FLUX_ENGINEERING_AGENT - Technical analysis

### PostgreSQL Module
Creates PostgreSQL Managed Service for OLTP workloads.

```hcl
module "postgres" {
  source = "./modules/postgres"
  
  postgres_database_name = "FLUX_OPERATIONS_POSTGRES"
  instance_size          = "S"
  
  snowflake_database = module.database.database_name
  warehouse          = module.warehouses.primary_warehouse_name
  
  create_external_access = true
  create_cdc_pipeline    = true
}
```

**Resources Created:**
- PostgreSQL Managed Service instance
- Network rule for SPCS connectivity
- Secret for credentials
- External Access Integration
- CDC stream and task for Snowflake→PostgreSQL sync

### SPCS Module
Creates Snowpark Container Services infrastructure.

```hcl
module "spcs" {
  source = "./modules/spcs"
  
  database_name  = module.database.database_name
  warehouse      = module.warehouses.primary_warehouse_name
  image_registry = "sfsehol-xxx.registry.snowflakecomputing.com"
  
  # Compute pools
  create_interactive_pool = true
  create_streaming_pool   = true
  
  # Services
  create_ops_center = true
  create_data_forge = true
  
  external_access_integration = module.postgres.external_access_integration
  postgres_host               = module.postgres.postgres_host
}
```

**Resources Created:**
- Image repository
- Compute pools (Interactive, Streaming)
- Flux Ops Center service
- Flux Data Forge service
- Service URL functions

---

## Environment Configurations

### Development (`dev.tfvars`)
```hcl
environment            = "dev"
database_name          = "FLUX_DEV"
primary_warehouse_size = "XSMALL"
large_warehouse_size   = "SMALL"
enable_spcs            = false
enable_postgres        = false
```

### Staging (`staging.tfvars`)
```hcl
environment            = "staging"
database_name          = "FLUX_STAGING"
primary_warehouse_size = "SMALL"
large_warehouse_size   = "MEDIUM"
enable_spcs            = true
enable_postgres        = true
```

### Production (`prod.tfvars`)
```hcl
environment            = "prod"
database_name          = "FLUX_PROD"
primary_warehouse_size = "MEDIUM"
large_warehouse_size   = "LARGE"
enable_spcs            = true
enable_postgres        = true

# Higher compute pool limits
interactive_pool_max_nodes = 5
streaming_pool_max_nodes   = 3
```

---

## State Management

### Local State (Default)
```bash
# State stored in terraform.tfstate
terraform apply -var-file="environments/dev.tfvars"
```

### Remote State (Recommended for Teams)
```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "flux-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "flux-terraform-locks"
  }
}
```

Or use Snowflake stage:
```hcl
terraform {
  backend "s3" {
    # Use Snowflake-compatible S3 endpoint
    endpoint = "s3.us-west-2.amazonaws.com"
    bucket   = "snowflake-terraform-state"
    key      = "flux/terraform.tfstate"
  }
}
```

---

## Common Operations

### View Current State
```bash
terraform show
```

### Import Existing Resources
```bash
# Import existing database
terraform import module.database.snowflake_database.flux FLUX_PROD

# Import existing warehouse
terraform import module.warehouses.snowflake_warehouse.primary FLUX_WH
```

### Destroy Specific Module
```bash
terraform destroy -target=module.cortex_search -var-file="environments/dev.tfvars"
```

### Refresh State
```bash
terraform refresh -var-file="environments/dev.tfvars"
```

---

## Troubleshooting

### Provider Limitations
Some Snowflake features aren't natively supported. We use `snowflake_unsafe_execute`:

```hcl
# Example: Cortex Agent (not natively supported)
resource "snowflake_unsafe_execute" "grid_analyst_agent" {
  execute = <<-SQL
    CREATE OR REPLACE CORTEX AGENT ...
  SQL
  
  revert = "DROP CORTEX AGENT IF EXISTS ..."
}
```

### Common Errors

**Error: Role does not exist**
```bash
# Ensure you're using a role with sufficient privileges
export SNOWFLAKE_ROLE="ACCOUNTADMIN"
```

**Error: Object already exists**
```bash
# Import existing object into state
terraform import <resource_address> <object_name>
```

**Error: Provider version mismatch**
```bash
# Update provider
terraform init -upgrade
```

---

## CI/CD Integration

### GitHub Actions
```yaml
# .github/workflows/terraform.yml
name: Terraform
on:
  push:
    branches: [main]
    paths: ['terraform/**']

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.6.0
      
      - name: Terraform Init
        run: terraform init
        working-directory: terraform
        
      - name: Terraform Plan
        run: terraform plan -var-file="environments/prod.tfvars" -out=tfplan
        working-directory: terraform
        env:
          SNOWFLAKE_ACCOUNT: ${{ secrets.SNOWFLAKE_ACCOUNT }}
          SNOWFLAKE_USER: ${{ secrets.SNOWFLAKE_USER }}
          SNOWFLAKE_PASSWORD: ${{ secrets.SNOWFLAKE_PASSWORD }}
      
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        run: terraform apply tfplan
        working-directory: terraform
```

---

## Best Practices

1. **Always plan before apply** - Review changes before execution
2. **Use remote state** - Enable team collaboration
3. **Lock state** - Prevent concurrent modifications
4. **Version pin providers** - Ensure reproducibility
5. **Use modules** - Keep configurations DRY
6. **Separate environments** - Use different tfvars files
7. **Protect sensitive data** - Use Terraform variables for secrets
8. **Document changes** - Commit meaningful messages

---

## Next Steps

After Terraform deployment:

1. **Upload semantic models**:
   ```bash
   snow stage put models/*.yaml @SEMANTIC_MODELS
   ```

2. **Build and push SPCS images** (from separate repositories):
   ```bash
   # Clone and build from external repos:
   # https://github.com/sfc-gh-abannerjee/flux-ops-center-spcs
   # https://github.com/sfc-gh-abannerjee/flux-utility-data-forge
   ```

3. **Load sample data**:
   ```bash
   snowsql -f scripts/sample_data/load_dimensions.sql
   ```

4. **Validate deployment**:
   ```bash
   ./cli/validate.sh
   ```
