# Git Deploy - EXECUTE IMMEDIATE FROM

Deploy Flux Utility Solutions directly from GitHub using Snowflake's native Git integration.

## Overview

This deployment method uses Snowflake's `EXECUTE IMMEDIATE FROM` feature to run SQL scripts
directly from the GitHub repository - no local files or staging required.

```
┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐
│    GitHub       │───────►│   Snowflake     │───────►│   Deployed      │
│  Repository     │  FETCH │ Git Repository  │ EXECUTE│   Objects       │
└─────────────────┘        └─────────────────┘        └─────────────────┘
```

## Quick Start

### 1. One-Time Setup

Run from Snowflake (requires ACCOUNTADMIN):

```sql
-- Create Git integration
CREATE OR REPLACE API INTEGRATION github_api_integration
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/Snowflake-Labs')
  ENABLED = TRUE;

-- Create repository reference
CREATE OR REPLACE GIT REPOSITORY flux_solutions_repo
  API_INTEGRATION = github_api_integration
  ORIGIN = 'https://github.com/Snowflake-Labs/flux-utility-solutions.git';

-- Fetch content
ALTER GIT REPOSITORY flux_solutions_repo FETCH;
```

### 2. Deploy

```sql
-- Deploy entire solution
EXECUTE IMMEDIATE FROM @flux_solutions_repo/branches/main/git_deploy/deploy_from_git.sql
  USING (
    database => 'FLUX_PROD',
    schema => 'PRODUCTION',
    warehouse => 'FLUX_WH'
  );
```

### 3. Update

```sql
-- Pull latest changes
ALTER GIT REPOSITORY flux_solutions_repo FETCH;

-- Re-deploy
EXECUTE IMMEDIATE FROM @flux_solutions_repo/branches/main/git_deploy/deploy_from_git.sql
  USING (database => 'FLUX_PROD', schema => 'PRODUCTION', warehouse => 'FLUX_WH');
```

## Files

| File | Purpose |
|------|---------|
| `setup_git_integration.sql` | One-time setup for Git integration |
| `deploy_from_git.sql` | Main deployment orchestrator |
| `deploy_cortex_only.sql` | Deploy only Cortex AI components |
| `deploy_tables_only.sql` | Deploy only table schemas |

## Parameters

The deployment script accepts these parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `database` | FLUX_PROD | Target database |
| `schema` | PRODUCTION | Target schema |
| `warehouse` | FLUX_WH | Compute warehouse |
| `admin_role` | ACCOUNTADMIN | Role for admin operations |
| `user_role` | PUBLIC | Role for user grants |

## Private Repository Setup

For private repositories, create a GitHub Personal Access Token:

```sql
-- Create secret
CREATE SECRET github_token
  TYPE = PASSWORD
  USERNAME = 'your-github-user'
  PASSWORD = 'ghp_xxxxxxxxxxxx';

-- Create integration with authentication
CREATE OR REPLACE API INTEGRATION github_api_integration
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/your-org')
  ALLOWED_AUTHENTICATION_SECRETS = (github_token)
  ENABLED = TRUE;

-- Create repo with credentials
CREATE OR REPLACE GIT REPOSITORY flux_solutions_repo
  API_INTEGRATION = github_api_integration
  GIT_CREDENTIALS = github_token
  ORIGIN = 'https://github.com/your-org/flux-utility-solutions.git';
```

## Branch Deployment

Deploy from specific branches:

```sql
-- Deploy from main
EXECUTE IMMEDIATE FROM @flux_solutions_repo/branches/main/git_deploy/deploy_from_git.sql;

-- Deploy from develop
EXECUTE IMMEDIATE FROM @flux_solutions_repo/branches/develop/git_deploy/deploy_from_git.sql;

-- Deploy from tag
EXECUTE IMMEDIATE FROM @flux_solutions_repo/tags/v1.0.0/git_deploy/deploy_from_git.sql;
```

## Troubleshooting

### Fetch fails
```sql
-- Check integration status
SHOW API INTEGRATIONS LIKE 'github%';

-- Check repository status
SHOW GIT REPOSITORIES;
```

### Permission denied
```sql
-- Grant repository access
GRANT READ ON GIT REPOSITORY flux_solutions_repo TO ROLE your_role;
```

### Script not found
```sql
-- List available files
LS @flux_solutions_repo/branches/main/scripts/;
```
