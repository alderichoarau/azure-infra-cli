# ------------------------------------------------------------------------------
# provision.ps1 - Create Azure resources via az CLI
#
# Resources created:
#   - Storage Account
#   - App Service (Python Web App -- uses shared plan plan-npr-prf2026)
#   - Function App (dedicated Storage + Python Function App on plan-npr-prf2026)
#   - Static Web App
#   - Azure Container Instance (ACI)
#
# All resources are tagged managed_by=cli for the Friday cleanup
# ------------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

# -- Variables -----------------------------------------------------------------
$Owner    = if ($env:OWNER) { $env:OWNER } else { "firstname-lastname" }
$RG       = if ($env:RESOURCE_GROUP) { $env:RESOURCE_GROUP } else { "rg-$Owner" }
$RGShared = "rg-shared-prf2026"
$Location = "francecentral"

# Tags applied to all resources - used by destroy.ps1
$Tags = @("managed_by=cli", "environment=tp", "owner=$Owner")

Write-Output "----------------------------------------------------"
Write-Output "  Azure Provisioning -- owner: $Owner"
Write-Output "  Resource Group : $RG"
Write-Output "  Region         : $Location"
Write-Output "----------------------------------------------------"

# -- 1. Business Storage Account -----------------------------------------------
Write-Output ""
Write-Output "> [1/5] Storage Account..."

# Azure constraint: 3-24 chars, lowercase letters and digits only
$SAName = "st$($Owner -replace '-', '')cli"

az storage account create `
    --name                    $SAName `
    --resource-group          $RG `
    --location                $Location `
    --sku                     Standard_LRS `
    --kind                    StorageV2 `
    --allow-blob-public-access false `
    --public-network-access   Disabled `
    --min-tls-version         TLS1_2 `
    --tags                    @Tags

Write-Output "[OK] Storage Account created: $SAName"

# -- 2. App Service (Python Web App) -------------------------------------------
# Resolve the full resource ID of the shared plan (lives in a different resource group)
$AppPlan = az appservice plan show `
    --name           "plan-npr-prf2026" `
    --resource-group $RGShared `
    --query          "id" -o tsv

Write-Output ""
Write-Output "> [2/5] App Service (Python Web App)..."

az webapp create `
    --name           "app-$Owner-cli" `
    --resource-group $RG `
    --plan           $AppPlan `
    --runtime        "PYTHON:3.11" `
    --tags           @Tags

# HTTPS only + TLS 1.2 minimum
az webapp update `
    --name           "app-$Owner-cli" `
    --resource-group $RG `
    --https-only     true

az webapp config set `
    --name            "app-$Owner-cli" `
    --resource-group  $RG `
    --min-tls-version 1.2

# Enable automatic build on deployment
az webapp config appsettings set `
    --name           "app-$Owner-cli" `
    --resource-group $RG `
    --settings       SCM_DO_BUILD_DURING_DEPLOYMENT=true ENVIRONMENT=tp

$AppUrl = az webapp show `
    --name           "app-$Owner-cli" `
    --resource-group $RG `
    --query          "defaultHostName" -o tsv

Write-Output "[OK] App Service created: https://$AppUrl"

# -- 3. Python Function App ----------------------------------------------------
Write-Output ""
Write-Output "> [3/5] Function App (dedicated Storage + shared plan)..."

# Storage account dedicated to Functions (required - separate from business storage)
$SAFnName = "stfn$($Owner -replace '-', '')"
$TagsFn   = $Tags + @("purpose=function-storage")

az storage account create `
    --name                  $SAFnName `
    --resource-group        $RG `
    --location              $Location `
    --sku                   Standard_LRS `
    --public-network-access Enabled `
    --min-tls-version       TLS1_2 `
    --tags                  @TagsFn

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

Write-Output "[OK] Function App created: https://$FnUrl"

# -- 4. Static Web App ---------------------------------------------------------
Write-Output ""
Write-Output "> [4/5] Static Web App..."

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

Write-Output "[OK] Static Web App created: https://$StappUrl"

# -- 5. Azure Container Instance (ACI) -----------------------------------------
Write-Output ""
Write-Output "> [5/5] Azure Container Instance (nginx)..."

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

# Verify the container was actually created (az container create can return 0 on Docker Hub rate limit errors)
az container show --name "aci-$Owner-cli" --resource-group $RG *>$null
if ($LASTEXITCODE -eq 0) {
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

    Write-Output "[OK] Container ACI created: http://$AciFqdn"
} else {
    Write-Output "[WARNING] Container ACI creation failed (Docker Hub rate limit?) -- retry manually"
    $AciFqdn = "N/A"
}

# -- Summary -------------------------------------------------------------------
Write-Output ""
Write-Output "----------------------------------------------------"
Write-Output "  Provisioning complete"
Write-Output ""
Write-Output "  Storage Account  : $SAName"
Write-Output "  App Service      : https://$AppUrl"
Write-Output "  Function App     : https://$FnUrl"
Write-Output "  Static Web App   : https://$StappUrl"
Write-Output "  Container ACI    : http://$AciFqdn"
Write-Output "----------------------------------------------------"
