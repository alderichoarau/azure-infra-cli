# ------------------------------------------------------------------------------
# destroy.ps1 - Delete Azure resources tagged managed_by=cli
#
# Does NOT delete the Resource Group - only CLI-managed resources
# Terraform resources (managed_by=terraform) are never touched
# App Service Plan is NOT deleted (shared plan in rg-shared-prf2026)
#
# Deletion order matters (Azure dependencies):
#   1. Apps (functionapp, webapp, container, staticwebapp)  <- child resources first
#   2. Application Insights                                 <- auto-created with Function App
#   3. Blob containers (api-logs, api-config)        
#   4. Network (NSG disassoc -> NSG -> NIC -> VNet)
#   5. Storage Accounts
# ------------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

$Owner    = if ($env:OWNER) { $env:OWNER } else { "firstname-lastname" }
$RG       = if ($env:RESOURCE_GROUP) { $env:RESOURCE_GROUP } else { "rg-$Owner" }

$SAName   = "st$($Owner -replace '-', '')cli"
$SAFnName = "stfn$($Owner -replace '-', '')"
$VnetName = "vnet-$Owner-cli"
$NsgName  = "nsg-frontend-$Owner-cli"
$NicName  = "nic-test-$Owner-cli"

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

# -- 5. Blob containers --------------------------------
# Must be done before deleting the storage account
Write-Output "> Deleting Blob containers..."
az storage account show --name $SAName --resource-group $RG *>$null
if ($LASTEXITCODE -eq 0) {
    $env:AZURE_STORAGE_CONNECTION_STRING = az storage account show-connection-string `
        --name           $SAName `
        --resource-group $RG `
        --query          connectionString `
        --output         tsv

    foreach ($Container in @("api-logs", "api-config")) {
        $Exists = az storage container exists --name $Container --query exists -o tsv 2>$null
        if ($Exists -eq "true") {
            az storage container delete --name $Container --timeout 30
            Write-Output "[OK] Container deleted: $Container"
        } else {
            Write-Output "[SKIP] Container not found: $Container"
        }
    }
} else {
    Write-Output "[SKIP] Storage Account not found -- containers already gone"
}

# -- 6. Network ----------------------------------------
# NSG must be disassociated from subnet before deletion
Write-Output "> Deleting Network resources (NSG -> NIC -> VNet)..."

# 6a. Disassociate NSG from subnet-frontend first
az network vnet subnet show --name "subnet-frontend" --vnet-name $VnetName --resource-group $RG *>$null
if ($LASTEXITCODE -eq 0) {
    $NsgAssoc = az network vnet subnet show `
        --name           "subnet-frontend" `
        --vnet-name      $VnetName `
        --resource-group $RG `
        --query          "networkSecurityGroup.id" -o tsv 2>$null
    if ($NsgAssoc -and $NsgAssoc -ne "null") {
        az network vnet subnet update `
            --name                   "subnet-frontend" `
            --vnet-name              $VnetName `
            --resource-group         $RG `
            --network-security-group ""
        Write-Output "   NSG disassociated from subnet-frontend"
    }
}

# 6b. Delete NSG
az network nsg show --name $NsgName --resource-group $RG *>$null
if ($LASTEXITCODE -eq 0) {
    az network nsg delete `
        --name           $NsgName `
        --resource-group $RG
    Write-Output "[OK] NSG deleted: $NsgName"
} else {
    Write-Output "[SKIP] NSG not found"
}

# 6c. Delete test NIC (if it exists)
az network nic show --name $NicName --resource-group $RG *>$null
if ($LASTEXITCODE -eq 0) {
    az network nic delete `
        --name           $NicName `
        --resource-group $RG
    Write-Output "[OK] NIC deleted: $NicName"
} else {
    Write-Output "[SKIP] NIC not found"
}

# 6d. Delete VNet (also deletes all subnets)
az network vnet show --name $VnetName --resource-group $RG *>$null
if ($LASTEXITCODE -eq 0) {
    az network vnet delete `
        --name           $VnetName `
        --resource-group $RG
    Write-Output "[OK] VNet deleted: $VnetName (subnets included)"
} else {
    Write-Output "[SKIP] VNet not found"
}

# -- 7. Storage Accounts -------------------------------------------------------
Write-Output "> Deleting Storage Accounts..."

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

az storage account show --name $SAName --resource-group $RG *>$null
if ($LASTEXITCODE -eq 0) {
    az storage account delete `
        --name           $SAName `
        --resource-group $RG `
        --yes
    Write-Output "[OK] Business Storage Account deleted: $SAName"
} else {
    Write-Output "[SKIP] $SAName not found"
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
Write-Output "  App Service Plan preserved (shared -- rg-shared-prf2026)"
Write-Output "  Terraform resources were not affected"
Write-Output "----------------------------------------------------"
