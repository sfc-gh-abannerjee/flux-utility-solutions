-- ============================================================================
-- Git Integration Setup for Flux Utility Solutions
-- ============================================================================
-- This script configures Snowflake Git integration to enable deployment
-- directly from GitHub using EXECUTE IMMEDIATE FROM.
--
-- Prerequisites:
--   1. ACCOUNTADMIN role or CREATE INTEGRATION privilege
--   2. GitHub Personal Access Token (for private repos)
--
-- Usage:
--   1. Replace {{ variables }} with your values
--   2. Run this script once to set up the integration
--   3. Use deploy_from_git.sql to deploy the solution
-- ============================================================================

-- Use appropriate role
USE ROLE {{ admin_role }};
USE DATABASE {{ database }};
USE SCHEMA {{ schema }};

-- ============================================================================
-- Step 1: Create Secret for GitHub Authentication (Private Repos Only)
-- ============================================================================
-- Skip this section if using a public repository

CREATE SECRET IF NOT EXISTS github_token
  TYPE = PASSWORD
  USERNAME = '{{ github_username }}'
  PASSWORD = '{{ github_pat }}';

-- ============================================================================
-- Step 2: Create API Integration for GitHub
-- ============================================================================

CREATE OR REPLACE API INTEGRATION github_api_integration
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/{{ github_org }}')
  -- For private repos, uncomment:
  -- ALLOWED_AUTHENTICATION_SECRETS = (github_token)
  ENABLED = TRUE;

-- ============================================================================
-- Step 3: Create Git Repository Reference
-- ============================================================================

CREATE OR REPLACE GIT REPOSITORY flux_utility_solutions_repo
  API_INTEGRATION = github_api_integration
  -- For private repos, uncomment:
  -- GIT_CREDENTIALS = github_token
  ORIGIN = 'https://github.com/{{ github_org }}/flux-utility-solutions.git';

-- ============================================================================
-- Step 4: Fetch Latest from Repository
-- ============================================================================

ALTER GIT REPOSITORY flux_utility_solutions_repo FETCH;

-- ============================================================================
-- Step 5: Verify Setup
-- ============================================================================

-- List available branches
SHOW GIT BRANCHES IN flux_utility_solutions_repo;

-- List files in scripts directory
LS @flux_utility_solutions_repo/branches/main/scripts/;

-- ============================================================================
-- Grant Usage to Deployment Role
-- ============================================================================

GRANT USAGE ON INTEGRATION github_api_integration TO ROLE {{ user_role }};
GRANT READ ON GIT REPOSITORY flux_utility_solutions_repo TO ROLE {{ user_role }};

-- ============================================================================
-- Next Steps
-- ============================================================================
-- 
-- Run deploy_from_git.sql to deploy the solution:
--   EXECUTE IMMEDIATE FROM @flux_utility_solutions_repo/branches/main/git_deploy/deploy_from_git.sql
--     USING (database => 'FLUX_PROD', schema => 'PRODUCTION', warehouse => 'FLUX_WH');
--
