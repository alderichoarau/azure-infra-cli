# Contributing

## Getting started

```bash
git clone https://github.com/alderichoarau/azure-infra-cli.git
cd azure-infra-cli
az login
```

## Project structure

```
azure-infra-cli/
├── bash/
│   ├── provision.sh     # creates all resources with tags
│   └── destroy.sh       # deletes only resources tagged managed_by=cli
├── powershell/
│   ├── provision.ps1    # PowerShell equivalent of provision.sh
│   └── destroy.ps1      # PowerShell equivalent of destroy.sh
└── .github/
    └── workflows/
        ├── provision.yml  # manual trigger from GitHub Actions
        ├── cleanup.yml    # automatic every Friday at 18:00 UTC
        └── ci.yml         # ShellCheck, actionlint, PSScriptAnalyzer
```

## Testing locally

**Bash:**
```bash
export OWNER="firstname-lastname"
export RESOURCE_GROUP="rg-firstname-lastname"
az login
bash bash/provision.sh
```

**PowerShell:**
```powershell
$env:OWNER = "firstname-lastname"
$env:RESOURCE_GROUP = "rg-firstname-lastname"
az login
pwsh powershell/provision.ps1
```

## Commit message convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

| Prefix | Use case |
|--------|----------|
| `feat:` | New resource or feature |
| `fix:` | Bug fix |
| `ci:` | CI/CD changes |
| `docs:` | Documentation only |
| `chore:` | Maintenance (deps, config) |
| `refactor:` | Refactoring without behavior change |

Examples:
```
feat: add Key Vault provisioning
fix: use az tag update for Static Web App
ci: add PSScriptAnalyzer job
```

## Pull request process

1. Create a branch from `main`
2. Make your changes and test locally
3. Ensure CI passes (ShellCheck, actionlint, PSScriptAnalyzer)
4. Open a PR — the template will guide you through the checklist
5. Request a review from `@alderichoarau`

## Key rules

- All resources **must** be tagged `managed_by=cli`
- Do **not** delete or modify the App Service Plan `plan-npr-prf2026`
- Do **not** commit secrets, `.env` files, or Azure credentials
- Keep bash and PowerShell scripts in sync when adding resources
