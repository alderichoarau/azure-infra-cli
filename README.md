# azure-infra-cli

> Provisioning Azure infrastructure with az CLI — Bash scripts with GitHub Actions automation

---

## Provisioned Resources

| Resource | Name | Description |
|----------|------|-------------|
| Storage Account | `st{owner}cli` | General-purpose object storage |
| App Service Plan | `plan-{owner}-cli` | Compute capacity (B1 Linux) |
| App Service | `app-{owner}-cli` | Python 3.11 Web App |
| Function App | `fn-{owner}-cli` | Serverless Python functions (Consumption) |
| Static Web App | `stapp-{owner}-cli` | Static site hosting |
| Container (ACI) | `aci-{owner}-cli` | Publicly accessible nginx container |

All resources are tagged `managed_by=cli` — they are automatically deleted every Friday evening without touching the Resource Group or Terraform resources.

---

## Structure

```
azure-infra-cli/
├── bash/
│   ├── provision.sh     # creates all resources with tags
│   └── destroy.sh       # deletes only resources tagged managed_by=cli
└── .github/
    └── workflows/
        ├── provision.yml  # manual trigger from GitHub Actions
        └── cleanup.yml    # automatic every Friday at 18:00 UTC
```

---

## Setup

### 1. GitHub Secrets to configure

In **Settings → Secrets and variables → Actions**:

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | Service principal ID (OIDC) |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Subscription ID |
| `AZURE_RESOURCE_GROUP` | Your resource group name (`rg-firstname-lastname`) |
| `AZURE_OWNER` | Your firstname-lastname (`firstname-lastname`) |

### 2. Provision resources

**Via GitHub Actions (recommended):**

Go to **Actions → Provision Azure Resources → Run workflow** → enter your firstname-lastname.

**Locally:**
```bash
export OWNER="firstname-lastname"
export RESOURCE_GROUP="rg-firstname-lastname"
az login
bash bash/provision.sh
```

### 3. Destroy resources

**Automatic:** every Friday at 18:00 UTC (20:00 Paris), the `cleanup.yml` workflow deletes all `managed_by=cli` resources.

**Manual via GitHub Actions:**

Go to **Actions → Friday Evening Cleanup → Run workflow**

**Locally:**
```bash
export OWNER="firstname-lastname"
export RESOURCE_GROUP="rg-firstname-lastname"
bash bash/destroy.sh
```

---

## Tags and coexistence with Terraform

| Tag | Managed by | Deleted by cleanup.yml |
|-----|-----------|------------------------|
| `managed_by=cli` | `provision.sh` | ✅ yes |
| `managed_by=terraform` | Terraform | ❌ never |

Terraform resources in the same Resource Group are never touched by this script.

---

Azure DevSecOps Training — Simplon
