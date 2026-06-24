# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability (exposed secret, misconfigured permission, insecure default), please **do not open a public issue**.

Report it privately by emailing: **alderic.hoarau@gmail.com**

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact

You will receive a response within 48 hours.

## Security practices in this project

- All Azure resources are provisioned with least-privilege OIDC authentication (no long-lived credentials)
- Secrets are stored in GitHub Secrets, never hardcoded
- Resources are tagged `managed_by=cli` and cleaned up automatically every Friday
- Terraform resources (`managed_by=terraform`) are never touched by these scripts
