# Deployment Architecture

Multiple deployment paths for different team preferences and environments.

---

## Deployment Paths

All paths deploy identical infrastructure - choose based on your team's preferences:

```mermaid
flowchart TB
    REPO["flux-utility-solutions/"]
    
    subgraph Paths["DEPLOYMENT OPTIONS"]
        SQL["SQL Scripts"] ~~~ NB["Notebooks"] ~~~ GIT["Git Integration"] ~~~ CLI["CLI"] ~~~ TF["Terraform"]
    end
    
    REPO --> Paths
    
    style REPO fill:#37474f,color:#fff
    style Paths fill:#1565c0,color:#fff
    style SQL fill:#2e7d32,color:#fff
    style NB fill:#ef6c00,color:#fff
    style GIT fill:#7b1fa2,color:#fff
    style CLI fill:#c62828,color:#fff
    style TF fill:#00838f,color:#fff
```

| Path | Best For | Key Feature |
|------|----------|-------------|
| **SQL Scripts** | Learning, auditing | Full visibility into each step |
| **Notebooks** | POC workshops | Interactive, documented execution |
| **Git Integration** | Modern DevOps | EXECUTE IMMEDIATE FROM repository |
| **CLI** | Quick demos | Single-command deployment |
| **Terraform** | Enterprise | Multi-environment, state management |

---

## Deployment Phases

Regardless of path chosen, deployment follows these phases:

```mermaid
flowchart TB
    subgraph P1["PHASE 1-3: FOUNDATION"]
        A1["Infrastructure"] ~~~ A2["Reference Data"] ~~~ A3["Core Tables"]
    end
    
    subgraph P2["PHASE 4-6: ANALYTICS"]
        B1["Views & Dynamic Tables"] ~~~ B2["Streamlit Apps"] ~~~ B3["Notebooks"]
    end
    
    subgraph P3["PHASE 7-10: FINALIZATION"]
        C1["ML Features"] ~~~ C2["Security"] ~~~ C3["Seed Data"] ~~~ C4["Validation"]
    end
    
    P1 --> P2 --> P3
    
    style P1 fill:#1565c0,color:#fff
    style P2 fill:#ef6c00,color:#fff
    style P3 fill:#2e7d32,color:#fff
```

### Phase Details

| Phase | Scripts | Purpose |
|-------|---------|---------|
| **1** | Infrastructure | Database, schemas, warehouse |
| **2** | Reference Data | Substations, circuits |
| **3** | Core Tables | Transformers, meters, customers |
| **4** | Views | Dynamic tables, analytics views |
| **5** | Apps | Streamlit applications |
| **6** | Notebooks | Setup and demo notebooks |
| **7** | ML | Model registry, features |
| **8** | Security | RBAC roles and grants |
| **9** | Seed Data | Sample data loading |
| **10** | Validation | Verification queries |

---

## Path-Specific Instructions

### SQL Scripts

Manual execution with full control:

```bash
# Execute each phase manually
snowsql -f sql/01_infrastructure.sql
snowsql -f sql/02_reference_data.sql
# ... continue through all phases
```

### Notebooks

Interactive workshop execution:

1. Import `notebooks/00_SETUP.ipynb` into Snowflake
2. Run cells sequentially
3. Verify outputs at each step

### Git Integration

GitOps workflow using repository stages:

```sql
-- Execute directly from Git repository
EXECUTE IMMEDIATE FROM @flux_repo/branches/main/sql/01_infrastructure.sql;
```

### CLI

Single-command deployment:

```bash
./cli/quickstart.sh
# Or with custom parameters:
./cli/quickstart.sh --database MY_DB --connection my_connection
```

### Terraform

Enterprise multi-environment:

```bash
cd terraform/
terraform init
terraform plan -var-file="environments/dev.tfvars"
terraform apply -var-file="environments/dev.tfvars"
```

---

## What Gets Deployed

```mermaid
flowchart TB
    subgraph DB["DATABASE: FLUX_UTILITY_SOLUTIONS"]
        subgraph PROD["PRODUCTION SCHEMA"]
            P1["Substations"] ~~~ P2["Transformers"] ~~~ P3["Meters"] ~~~ P4["Customers"]
        end
        
        subgraph APPS["APPLICATIONS SCHEMA"]
            A1["Semantic Views"] ~~~ A2["Search Services"] ~~~ A3["Streamlit Apps"]
        end
        
        subgraph SEC["SECRETS SCHEMA"]
            S1["API Keys"] ~~~ S2["Configs"]
        end
    end
    
    style DB fill:#37474f,color:#fff
    style PROD fill:#1565c0,color:#fff
    style APPS fill:#ef6c00,color:#fff
    style SEC fill:#2e7d32,color:#fff
```

---

## Environment Configuration

### Connection Setup

```toml
# ~/.snowflake/connections.toml
[flux_dev]
account = "your_account"
user = "your_user"
authenticator = "externalbrowser"
database = "FLUX_UTILITY_SOLUTIONS"
schema = "PRODUCTION"
warehouse = "FLUX_WH"
```

### Terraform Variables

```hcl
# environments/dev.tfvars
environment     = "dev"
database_name   = "FLUX_DEV"
warehouse_size  = "XSMALL"
auto_suspend    = 60
```

---

## Validation

After deployment, verify with:

```sql
-- Check infrastructure
SHOW DATABASES LIKE 'FLUX%';
SHOW SCHEMAS IN DATABASE FLUX_UTILITY_SOLUTIONS;
SHOW TABLES IN SCHEMA PRODUCTION;

-- Verify data
SELECT COUNT(*) FROM PRODUCTION.SUBSTATIONS;
SELECT COUNT(*) FROM PRODUCTION.TRANSFORMERS;
```

See [DEPLOYMENT.md](./DEPLOYMENT.md) for detailed step-by-step instructions.
