# Variable Templating Guide

## What Are Variables and Why Do We Use Them?

When you deploy Flux Utility Solutions, you need to specify things like:
- **Database name**: Where should everything be created?
- **Warehouse name**: What compute resources should be used?
- **Role names**: Who should have access?

Instead of hardcoding these values (which would force everyone to use the same names), we use **variables** - placeholders that you fill in with your own values.

Think of it like a form with blank fields:
```
Create database _________ 
```

You fill in the blank with whatever name works for your organization.

---

## The Two Variable Syntaxes

Flux uses two different variable styles depending on how you're deploying:

### 1. Snow CLI Style: `<% variable %>`

Used when running scripts with Snow CLI's `-D` flag.

**In the script:**
```sql
CREATE DATABASE IDENTIFIER('<% database %>');
```

**How you run it:**
```bash
snow sql -f scripts/01_database_infrastructure.sql \
    -D "database=MY_COMPANY_FLUX"
```

**What Snowflake sees:**
```sql
CREATE DATABASE IDENTIFIER('MY_COMPANY_FLUX');
```

### 2. Snowsight Notebook Style: `$variable`

Used when running .sql notebooks in Snowsight.

**In the notebook:**
```sql
SET database_name = 'MY_COMPANY_FLUX';
CREATE DATABASE IDENTIFIER($database_name);
```

You set variables at the top of the notebook, then use them throughout.

---

## Step-by-Step: Running Your First Script

Let's walk through deploying the first script.

### Step 1: Decide Your Values

Pick names that make sense for your organization:

| Variable | Example Value | Description |
|----------|--------------|-------------|
| `database` | `FLUX_PROD` | Your database name |
| `warehouse` | `FLUX_WH` | Your warehouse prefix |
| `admin_role` | `FLUX_ADMIN` | Role for administrators |
| `user_role` | `FLUX_USER` | Role for end users |

### Step 2: Run the Command

```bash
snow sql -f scripts/01_database_infrastructure.sql \
    -D "database=FLUX_PROD" \
    -D "admin_role=FLUX_ADMIN" \
    -D "user_role=FLUX_USER" \
    -c your_connection_name
```

**Breaking this down:**
- `snow sql` - Run SQL using Snowflake CLI
- `-f scripts/01_...sql` - The file to run
- `-D "database=FLUX_PROD"` - Replace `<% database %>` with `FLUX_PROD`
- `-D "admin_role=FLUX_ADMIN"` - Replace `<% admin_role %>` with `FLUX_ADMIN`
- `-c your_connection_name` - Which Snowflake connection to use

### Step 3: Verify It Worked

```bash
snow sql -q "SHOW DATABASES LIKE 'FLUX%'" -c your_connection_name
```

You should see your new database listed.

---

## All Variables Used in Flux

| Variable | Used In | Description | Example |
|----------|---------|-------------|---------|
| `database` | All scripts | Database name | `FLUX_PROD` |
| `warehouse` | Most scripts | Warehouse prefix | `FLUX_WH` |
| `admin_role` | Scripts 01, 16 | Admin role name | `FLUX_ADMIN` |
| `user_role` | Scripts 01, 16 | User role name | `FLUX_USER` |
| `compute_pool` | Script 13 | SPCS compute pool | `FLUX_POOL` |
| `spcs_service` | Script 13 | SPCS service name | `FLUX_OPS_CENTER` |

---

## Common Mistakes (and How to Fix Them)

### Mistake 1: Forgetting Quotes Around Values

**Wrong:**
```bash
snow sql -f script.sql -D database=FLUX_PROD  # Missing quotes
```

**Right:**
```bash
snow sql -f script.sql -D "database=FLUX_PROD"
```

### Mistake 2: Using Wrong Variable Syntax

Each deployment path uses a specific syntax:

| Path | Syntax | Example |
|------|--------|---------|
| Snow CLI | `<% var %>` | `<% database %>` |
| Snowsight notebooks | `$var` | `$database_name` |
| Git EXECUTE IMMEDIATE | `$var` | `$database` |
| Terraform | `var.name` | `var.database_name` |

### Mistake 3: Running Scripts Out of Order

Scripts have dependencies. For example, script 06 needs tables from scripts 03-05.

**Always run in numerical order:**
```bash
snow sql -f scripts/01_database_infrastructure.sql -D "..."
snow sql -f scripts/02_warehouses.sql -D "..."
snow sql -f scripts/03_substations_transformers.sql -D "..."
# ... and so on
```

### Mistake 4: Forgetting the Connection Flag

If you have multiple Snowflake accounts configured:

```bash
# This might use the wrong account:
snow sql -f script.sql -D "database=FLUX_PROD"

# Specify your connection explicitly:
snow sql -f script.sql -D "database=FLUX_PROD" -c my_prod_connection
```

---

## Quick Reference Card

### Snow CLI Deployment
```bash
# Set your variables
DB="FLUX_PROD"
WH="FLUX_WH"
ADMIN="FLUX_ADMIN"
USER="FLUX_USER"
CONN="your_connection"

# Run a script
snow sql -f scripts/01_database_infrastructure.sql \
    -D "database=$DB" \
    -D "warehouse=$WH" \
    -D "admin_role=$ADMIN" \
    -D "user_role=$USER" \
    -c $CONN
```

### Snowsight Notebook
```sql
-- Set variables at the top
SET database_name = 'FLUX_PROD';
SET warehouse_prefix = 'FLUX_WH';
SET admin_role = 'FLUX_ADMIN';

-- Use them in queries
USE DATABASE IDENTIFIER($database_name);
```

### Git Integration (EXECUTE IMMEDIATE FROM)
```sql
EXECUTE IMMEDIATE FROM @my_repo/branches/main/scripts/01_database_infrastructure.sql
USING (
    database => 'FLUX_PROD',
    warehouse => 'FLUX_WH',
    admin_role => 'FLUX_ADMIN',
    user_role => 'FLUX_USER'
);
```

---

## Need Help?

- **Snow CLI not found?** Install with: `pip install snowflake-cli`
- **Connection issues?** Run: `snow connection test -c your_connection`
- **Variable not substituted?** Check spelling matches exactly (case-sensitive)

See [DEPLOYMENT.md](DEPLOYMENT.md) for full deployment instructions.
