# ──────────────────────────────────────────────────────────────────────────────
# provision.ps1 — Create Azure resources via az CLI
#
# Resources created:
#   - Storage Account
#   - App Service (Python Web App — uses shared plan plan-npr-prf2026)
#   - Function App (dedicated Storage + Python Function App on plan-npr-prf2026)
#   - Static Web App
#   - Azure Container Instance (ACI)
#
# All resources are tagged managed_by=cli for the Friday cleanup
# ──────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

# ── Variables ─────────────────────────────────────────────────────────────────
$Owner         = if ($env:OWNER) { $env:OWNER } else { "firstname-lastname" }
$RG            = if ($env:RESOURCE_GROUP) { $env:RESOURCE_GROUP } else { "rg-$Owner" }
$RGShared      = "rg-shared-prf2026"
$Location      = "francecentral"

# Tags applied to all resources — used by destroy.ps1
$Tags = @("managed_by=cli", "environment=tp", "owner=$Owner")

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "  Azure Provisioning — owner: $Owner"
Write-Host "  Resource Group : $RG"
Write-Host "  Region         : $Location"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Business Storage Account ───────────────────────────────────────────────
Write-Host ""
Write-Host "▶ [1/5] Storage Account..."

# Azure constraint: 3-24 chars, lowercase letters and digits only
$SAName = "st$($Owner -replace '-', '')cli"

az storage account create `
  --name                   $SAName `
  --resource-group         $RG `
  --location               $Location `
  --sku                    Standard_LRS `
  --kind                   StorageV2 `
  --allow-blob-public-access false `
  --tags                   @Tags

Write-Host "✅ Storage Account created: $SAName"

# ── 2. App Service (Python Web App) ───────────────────────────────────────────
# Resolve the full resource ID of the shared plan (lives in a different resource group)
$AppPlan = az appservice plan show `
  --name           "plan-npr-prf2026" `
  --resource-group $RGShared `
  --query          "id" -o tsv

Write-Host ""
Write-Host "▶ [2/5] App Service (Python Web App)..."

az webapp create `
  --name           "app-$Owner-cli" `
  --resource-group $RG `
  --plan           $AppPlan `
  --runtime        "PYTHON:3.11" `
  --tags           @Tags

# Enable automatic build on deployment
az webapp config appsettings set `
  --name           "app-$Owner-cli" `
  --resource-group $RG `
  --settings       SCM_DO_BUILD_DURING_DEPLOYMENT=true ENVIRONMENT=tp

$AppUrl = az webapp show `
  --name           "app-$Owner-cli" `
  --resource-group $RG `
  --query          "defaultHostName" -o tsv

Write-Host "✅ App Service created: https://$AppUrl"

# ── 3. Python Function App ────────────────────────────────────────────────────
Write-Host ""
Write-Host "▶ [3/5] Function App (dedicated Storage + shared plan)..."

# Storage account dedicated to Functions (required — separate from business storage)
$SAFnName = "stfn$($Owner -replace '-', '')"
$TagsFn   = $Tags + @("purpose=function-storage")

az storage account create `
  --name           $SAFnName `
  --resource-group $RG `
  --location       $Location `
  --sku            Standard_LRS `
  --tags           @TagsFn

az functionapp create `
  --name            "fn-$Owner-cli" `
  --resource-group  $RG `
  --storage-account $SAFnName `
  --plan            $AppPlan `
  --runtime         python `
  --runtime-version 3.11 `
  --os-type         Linux `
  --tags            @Tags

$FnUrl = az functionapp show `
  --name           "fn-$Owner-cli" `
  --resource-group $RG `
  --query          "defaultHostName" -o tsv

Write-Host "✅ Function App created: https://$FnUrl"

# ── 4. Static Web App ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "▶ [4/5] Static Web App..."

az staticwebapp create `
  --name           "stapp-$Owner-cli" `
  --resource-group $RG `
  --location       "westeurope"

# az staticwebapp create does not support --tags, so we tag the resource after creation
$StappId = az staticwebapp show `
  --name           "stapp-$Owner-cli" `
  --resource-group $RG `
  --query          "id" -o tsv

az tag update `
  --resource-id $StappId `
  --operation   Merge `
  --tags        @Tags

$StappUrl = az staticwebapp show `
  --name           "stapp-$Owner-cli" `
  --resource-group $RG `
  --query          "defaultHostname" -o tsv

Write-Host "✅ Static Web App created: https://$StappUrl"

# ── 5. Azure Container Instance (ACI) ─────────────────────────────────────────
Write-Host ""
Write-Host "▶ [5/5] Azure Container Instance (nginx)..."

az container create `
  --name           "aci-$Owner-cli" `
  --resource-group $RG `
  --image          "nginx:latest" `
  --cpu            0.5 `
  --memory         0.5 `
  --ports          80 `
  --ip-address     Public `
  --dns-name-label "aci-$Owner-cli" `
  --os-type        Linux `
  --environment-variables OWNER="$Owner" ENVIRONMENT="tp"

# az container create does not support --tags, so we tag the resource after creation
$AciId = az container show `
  --name           "aci-$Owner-cli" `
  --resource-group $RG `
  --query          "id" -o tsv

az tag update `
  --resource-id $AciId `
  --operation   Merge `
  --tags        @Tags

$AciFqdn = az container show `
  --name           "aci-$Owner-cli" `
  --resource-group $RG `
  --query          "ipAddress.fqdn" -o tsv

Write-Host "✅ Container ACI created: http://$AciFqdn"

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "  ✅ Provisioning complete"
Write-Host ""
Write-Host "  Storage Account  : $SAName"
Write-Host "  App Service      : https://$AppUrl"
Write-Host "  Function App     : https://$FnUrl"
Write-Host "  Static Web App   : https://$StappUrl"
Write-Host "  Container ACI    : http://$AciFqdn"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
