# ──────────────────────────────────────────────────────────────────────────────
# destroy.ps1 — Delete Azure resources tagged managed_by=cli
#
# ⚠️  Does NOT delete the Resource Group — only CLI-managed resources
# ⚠️  Terraform resources (managed_by=terraform) are never touched
#
# Deletion order matters (Azure dependencies):
#   1. Apps (webapp, functionapp, container, staticwebapp)  ← child resources
#   2. Storage Accounts                                     ← independent
#
# Note: App Service Plan is intentionally NOT deleted
# ──────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

$Owner = if ($env:OWNER) { $env:OWNER } else { "firstname-lastname" }
$RG    = if ($env:RESOURCE_GROUP) { $env:RESOURCE_GROUP } else { "rg-$Owner" }

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "  🗑️  Azure Cleanup — owner: $Owner"
Write-Host "  Resource Group : $RG"
Write-Host "  Target tag     : managed_by=cli"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# List the resources that will be deleted before starting
Write-Host ""
Write-Host "Target resources (tag managed_by=cli):"
az resource list `
  --resource-group $RG `
  --query          "[?tags.managed_by=='cli'].{Name:name, Type:type}" `
  --output         table

Write-Host ""

# ── 1. Function App ───────────────────────────────────────────────────────────
Write-Host "▶ Deleting Function App..."
$fnExists = az functionapp show --name "fn-$Owner-cli" --resource-group $RG 2>$null
if ($LASTEXITCODE -eq 0) {
  az functionapp delete `
    --name           "fn-$Owner-cli" `
    --resource-group $RG
  Write-Host "✅ Function App deleted"
} else {
  Write-Host "⏭️  Function App not found — skipped"
}

# ── 2. Web App ────────────────────────────────────────────────────────────────
Write-Host "▶ Deleting App Service..."
$webExists = az webapp show --name "app-$Owner-cli" --resource-group $RG 2>$null
if ($LASTEXITCODE -eq 0) {
  az webapp delete `
    --name           "app-$Owner-cli" `
    --resource-group $RG
  Write-Host "✅ App Service deleted"
} else {
  Write-Host "⏭️  App Service not found — skipped"
}

# ── 3. Container ACI ──────────────────────────────────────────────────────────
Write-Host "▶ Deleting Container ACI..."
$aciExists = az container show --name "aci-$Owner-cli" --resource-group $RG 2>$null
if ($LASTEXITCODE -eq 0) {
  az container delete `
    --name           "aci-$Owner-cli" `
    --resource-group $RG `
    --yes
  Write-Host "✅ Container ACI deleted"
} else {
  Write-Host "⏭️  Container ACI not found — skipped"
}

# ── 4. Static Web App ─────────────────────────────────────────────────────────
Write-Host "▶ Deleting Static Web App..."
$stappExists = az staticwebapp show --name "stapp-$Owner-cli" --resource-group $RG 2>$null
if ($LASTEXITCODE -eq 0) {
  az staticwebapp delete `
    --name           "stapp-$Owner-cli" `
    --resource-group $RG `
    --yes
  Write-Host "✅ Static Web App deleted"
} else {
  Write-Host "⏭️  Static Web App not found — skipped"
}

# ── 5. Storage Accounts ───────────────────────────────────────────────────────
Write-Host "▶ Deleting Storage Accounts..."

$SAName = "st$($Owner -replace '-', '')cli"
$saExists = az storage account show --name $SAName --resource-group $RG 2>$null
if ($LASTEXITCODE -eq 0) {
  az storage account delete `
    --name           $SAName `
    --resource-group $RG `
    --yes
  Write-Host "✅ Storage Account deleted: $SAName"
} else {
  Write-Host "⏭️  $SAName not found — skipped"
}

$SAFnName = "stfn$($Owner -replace '-', '')"
$saFnExists = az storage account show --name $SAFnName --resource-group $RG 2>$null
if ($LASTEXITCODE -eq 0) {
  az storage account delete `
    --name           $SAFnName `
    --resource-group $RG `
    --yes
  Write-Host "✅ Function Storage Account deleted: $SAFnName"
} else {
  Write-Host "⏭️  $SAFnName not found — skipped"
}

# ── Final check ───────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Remaining resources with tag managed_by=cli:"
$Remaining = az resource list `
  --resource-group $RG `
  --query          "length([?tags.managed_by=='cli'])" | ConvertFrom-Json

if ($Remaining -eq 0) {
  Write-Host "✅ No CLI resources remaining"
} else {
  Write-Host "⚠️  $Remaining resource(s) not deleted — check manually"
  az resource list `
    --resource-group $RG `
    --query          "[?tags.managed_by=='cli'].{Name:name, Type:type}" `
    --output         table
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "  ✅ Cleanup complete — Resource Group preserved"
Write-Host "  Terraform resources were not affected"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
