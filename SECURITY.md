# Security

For detailed security documentation including role-based access control (RBAC), permissions, and best practices, see:

**[docs/SECURITY.md](./docs/SECURITY.md)**

## Quick Reference

- **Role hierarchy**: FLUX_ADMIN → FLUX_USER / FLUX_ETL / FLUX_SERVICE → FLUX_ANALYST
- **Secrets management**: Store in SECRETS schema, never commit to git
- **Audit logging**: Use `SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY`

## Reporting Security Issues

If you discover a security vulnerability, please report it responsibly:

1. **Do not** create a public GitHub issue
2. Email: security@snowflake.com
3. Include steps to reproduce the issue
