# Contributing to Flux Utility Solutions

Thank you for your interest in contributing to Flux Utility Solutions!

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Create a feature branch (`git checkout -b feature/amazing-feature`)

## Development Setup

```bash
# Clone and setup
git clone https://github.com/YOUR_USERNAME/flux-utility-solutions.git
cd flux-utility-solutions

# Install Python dependencies (for generators/scripts)
pip install -r requirements.txt

# Configure Snowflake CLI connection
snow connection add
```

## Deployment Paths

This repo supports 5 deployment methods - choose your preferred approach:

| Path | Command | Best For |
|------|---------|----------|
| CLI Quick Start | `./cli/quickstart.sh` | Fastest setup |
| SQL Scripts | Run scripts in `scripts/` | Step-by-step control |
| Notebooks | Open notebooks in Snowsight | Workshops |
| Git Integration | `scripts/19_git_integration.sql` | GitOps |
| Terraform | `cd terraform && terraform apply` | Enterprise IaC |

## Code Standards

- **Python**: Follow PEP 8 style guidelines
- **SQL**: Use uppercase keywords, lowercase identifiers
- **Commits**: Use conventional commit messages (`feat:`, `fix:`, `docs:`)

## Pull Request Process

1. Ensure your changes work with at least one deployment path
2. Update documentation if needed
3. Submit PR with clear description of changes
4. Link related issues

## Testing

```bash
# Validate deployment
./cli/validate.sh

# Run Python generators
python generators/generate_all.py --size small --dry-run
```

## Documentation

- Update relevant docs in `docs/` for significant changes
- Keep README.md in sync with new features
- Add comments to SQL scripts explaining purpose

## Reporting Issues

- Use GitHub Issues for bugs and feature requests
- Include reproduction steps and environment details
- For security issues, see [docs/SECURITY.md](./docs/SECURITY.md)

## Related Repositories

Flux Utility Solutions is part of the Flux Utility Platform:

| Repository | Purpose |
|------------|---------|
| **Flux Utility Solutions** (this repo) | Core platform with Cortex AI |
| [Flux Data Forge](https://github.com/sfc-gh-abannerjee/flux-data-forge) | Synthetic data generation |
| [Flux Ops Center](https://github.com/sfc-gh-abannerjee/flux-ops-center-spcs) | Grid visualization |

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
