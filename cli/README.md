# Flux Utility Solutions - CLI Tools

Python CLI tools for automated deployment and validation.

## Prerequisites

```bash
pip install snowflake-cli pyyaml
```

Configure Snow CLI connection:
```bash
snow connection add --connection-name cpe_demo
```

## Tools

### deploy.py - Automated Deployment

Deploy Flux solution to any environment with template rendering.

```bash
# Dry run - show what would be executed
python deploy.py --env dev --all --dry-run

# Deploy specific scripts
python deploy.py --env dev --scripts 01,02,03

# Deploy range of scripts
python deploy.py --env staging --scripts 01-10

# Full production deployment
python deploy.py --env prod --all --connection prod_connection
```

### validate.py - Deployment Validation

Verify deployment matches expected state.

```bash
# Run all validation checks
python validate.py --env prod --check all

# Check specific components
python validate.py --env dev --check tables semantic

# Available checks:
#   - tables: Core production tables exist
#   - semantic: Semantic views deployed
#   - search: Cortex Search services active
#   - agents: Cortex Agents configured
#   - counts: Row counts within expected ranges
```

## Environment Configuration

Environments are defined in `scripts/config.yaml`:

| Environment | Database | Warehouse |
|-------------|----------|-----------|
| dev | FLUX_DEV | SI_DEMO_WH |
| staging | FLUX_STAGING | FLUX_STAGING_WH |
| prod | FLUX_PROD | FLUX_PROD_WH |
| si_demos | SI_DEMOS | SI_DEMO_WH |

## Workflow

### Initial Deployment

```bash
# 1. Dry run to verify
python deploy.py --env dev --all --dry-run

# 2. Deploy infrastructure (01-02)
python deploy.py --env dev --scripts 01-02

# 3. Deploy tables (03-07)
python deploy.py --env dev --scripts 03-07

# 4. Deploy AI components (08-10)
python deploy.py --env dev --scripts 08-10

# 5. Validate
python validate.py --env dev --check all
```

### Incremental Updates

```bash
# Deploy only changed scripts
python deploy.py --env prod --scripts 08  # Update semantic view

# Validate after changes
python validate.py --env prod --check semantic
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Validation failed |
| 2 | Configuration error |
