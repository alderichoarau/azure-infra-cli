# ------------------------------------------------------------------------------
# destroy.ps1 - Delete Azure resources tagged managed_by=cli
#
# Does NOT delete the Resource Group - only CLI-managed resources
# Terraform resources (managed_by=terraform) are never touched
#
# Deletion order matters (Azure dependencies):
#   1. Apps (webapp, functionapp, container, staticwebapp)  <- child resources
#   2. Storage Accounts                                     <- independent
#
# Note: App Service Plan is intentionally NOT deleted
# ------------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

$Owner = if ($env:OWNER) { $env:OWNER } else { "firstname-lastname" }
$RG    = if ($env:RESOURCE_GROUP) { $env:RESOURCE_GROUP } else { "rg-$Owner" }

Write-Output "----------------------------------------------------"
Write-Output "  Azure Cleanup -- owner: $Owner"
Write-Output "  Resource Group : $RG"
Write-Output "  Target tag     : managed_by=cli"
Write-Output "----------------------------------------------------"

# List the resources that will be deleted before starting
Write-Output ""
Write-Output "Target resources (tag managed_by=cli):"
az resource list `
  --resource-group $RG `
  --query          "[?tags.managed_by=='cli'].{Name:name, Type:type}" `
  --output         table

Write-Output ""

# -- 1. Function App -----------------------------------------------------------
Write-Output "> Deleting Function App..."
az functionapp show --name "fn-$Owner-cli" --resource-group $RG *>$null
if ($LASTEXITCODE -eq 0) {
    az functionapp delete `
        --name           "fn-$Owner-cli" `
        --resource-group $RG
    Write-Output "[OK] Function App deleted"
} else {
    Write-Output "[SKIP] Function App not found"
}

# -- 1b. Application Insights (auto-created with Function App) -----------------
Write-Output "> Deleting Application Insights..."
az monitor app-insights component show --app "fn-$Owner-cli" --resource-group $RG *>$null
if ($LASTEXITCODE -eq 0) {
    az monitor app-insights component delete `
        --app            "fn-$Owner-cli" `
        --resource-group $RG
    Write-Output "[OK] Application Insights deleted"
} else {
    Write-Output "[SKIP] Application Insights not found"
}

# -- 2. Web App ----------------------------------------------------------------
Write-Output "> Deleting App Service..."
az webapp show --name "app-$Owner-cli" --resource-group $RG *>$null
if ($LASTEXITCODE -eq 0) {
    az webapp delete `
        --name           "app-$Owner-cli" `
        --resource-group $RG
    Write-Output "[OK] App Service deleted"
} else {
    Write-Output "[SKIP] App Service not found"
}

# -- 3. Container ACI ----------------------------------------------------------
Write-Output "> Deleting Container ACI..."
az container show --name "aci-$Owner-cli" --resource-group $RG *>$null
if ($LASTEXITCODE -eq 0) {
    az container delete `
        --name           "aci-$Owner-cli" `
        --resource-group $RG `
        --yes
    Write-Output "[OK] Container ACI deleted"
} else {
    Write-Output "[SKIP] Container ACI not found"
}

# -- 4. Static Web App ---------------------------------------------------------
Write-Output "> Deleting Static Web App..."
az staticwebapp show --name "stapp-$Owner-cli" --resource-group $RG *>$null
if ($LASTEXITCODE -eq 0) {
    az staticwebapp delete `
        --name           "stapp-$Owner-cli" `
        --resource-group $RG `
        --yes
    Write-Output "[OK] Static Web App deleted"
} else {
    Write-Output "[SKIP] Static Web App not found"
}

# -- 5. Storage Accounts -------------------------------------------------------
Write-Output "> Deleting Storage Accounts..."

$SAName = "st$($Owner -replace '-', '')cli"
az storage account show --name $SAName --resource-group $RG *>$null
if ($LASTEXITCODE -eq 0) {
    az storage account delete `
        --name           $SAName `
        --resource-group $RG `
        --yes
    Write-Output "[OK] Storage Account deleted: $SAName"
} else {
    Write-Output "[SKIP] $SAName not found"
}

$SAFnName = "stfn$($Owner -replace '-', '')"
az storage account show --name $SAFnName --resource-group $RG *>$null
if ($LASTEXITCODE -eq 0) {
    az storage account delete `
        --name           $SAFnName `
        --resource-group $RG `
        --yes
    Write-Output "[OK] Function Storage Account deleted: $SAFnName"
} else {
    Write-Output "[SKIP] $SAFnName not found"
}

# -- Final check ---------------------------------------------------------------
Write-Output ""
Write-Output "Remaining resources with tag managed_by=cli:"
$Remaining = az resource list `
    --resource-group $RG `
    --query          "length([?tags.managed_by=='cli'])" | ConvertFrom-Json

if ($Remaining -eq 0) {
    Write-Output "[OK] No CLI resources remaining"
} else {
    Write-Output "[WARNING] $Remaining resource(s) not deleted -- check manually"
    az resource list `
        --resource-group $RG `
        --query          "[?tags.managed_by=='cli'].{Name:name, Type:type}" `
        --output         table
}

Write-Output ""
Write-Output "----------------------------------------------------"
Write-Output "  Cleanup complete -- Resource Group preserved"
Write-Output "  Terraform resources were not affected"
Write-Output "----------------------------------------------------"
