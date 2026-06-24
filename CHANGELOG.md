# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

---

## [1.1.0] - 2026-06-24

### Added
- PowerShell scripts (`powershell/provision.ps1`, `powershell/destroy.ps1`)
- Shell selector input (`bash` / `powershell`) in both GitHub Actions workflows
- PSScriptAnalyzer job in CI to lint PowerShell scripts
- Dependabot configuration for GitHub Actions dependency updates
- CODEOWNERS file — `@alderichoarau` as default reviewer
- Status badges (CI, Dependabot) in README
- `.gitignore`, `LICENSE` (MIT), `SECURITY.md`
- PR template and issue templates (bug report, feature request)

### Changed
- Workflow inputs now use `resource_group` instead of `owner` — `OWNER` is derived automatically
- `run-name` added to both workflows to display the resource group on each run
- App Service and Function App now use shared plan `plan-npr-prf2026` from `rg-shared-prf2026`
- Function App storage account renamed to `stfn{owner}` with tag `purpose=function-storage`
- Static Web App location fixed to `westeurope` (francecentral not supported)
- Tags now use Bash arrays and `az tag update` for resources that don't support `--tags`
- `az resource list` filtering switched from `--tag` to JMESPath query

### Fixed
- Docker Hub rate limit: ACI tagging now guarded by existence check
- `az container create` missing `--os-type Linux`
- ShellCheck SC2086 warnings: `$TAGS` and `$TAGS_FN` converted to arrays
- `$GITHUB_ENV` and `$GITHUB_STEP_SUMMARY` now properly quoted
- Function App storage account name truncated to stay within 24-char Azure limit

### Removed
- App Service Plan creation from `provision.sh` (uses shared plan instead)
- App Service Plan deletion from `destroy.sh` (not managed by this project)

---

## [1.0.0] - 2026-06-24

### Added
- Initial Bash provisioning scripts (`bash/provision.sh`, `bash/destroy.sh`)
- GitHub Actions workflows (`provision.yml`, `cleanup.yml`)
- CI workflow with ShellCheck and actionlint
- README in English with setup instructions
