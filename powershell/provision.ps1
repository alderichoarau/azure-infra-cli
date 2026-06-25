# ------------------------------------------------------------------------------
# provision.ps1 - Create Azure resources via az CLI
#
# Resources created:
#   1. Storage Account + Blob containers (private: api-logs / public: api-config)
#   2. App Service (Python Web App -- uses shared plan plan-npr-prf2026)
#   3. Function App (dedicated Storage + Python Function App on plan-npr-prf2026)
#   4. Static Web App
#   5. Azure Container Instance (ACI)
#   6. Blob containers (api-logs private / api-config public)
#   7. Network (VNet + subnets + NSG + rules)
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

# Network resource names
$VnetName = "vnet-$Owner-cli"
$NsgName  = "nsg-frontend-$Owner-cli"

Write-Output "----------------------------------------------------"
Write-Output "  Azure Provisioning -- owner: $Owner"
Write-Output "  Resource Group : $RG"
Write-Output "  Region         : $Location"
Write-Output "----------------------------------------------------"

# -- 1. Business Storage Account -----------------------------------------------
Write-Output ""
Write-Output "> [1/7] Storage Account..."

# Azure constraint: 3-24 chars, lowercase letters and digits only
$SAName = "st$($Owner -replace '-', '')cli"

az storage account create `
    --name                    $SAName `
    --resource-group          $RG `
    --location                $Location `
    --sku                     Standard_LRS `
    --kind                    StorageV2 `
    --allow-blob-public-access true `
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
Write-Output "> [2/7] App Service (Python Web App)..."

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
Write-Output "> [3/7] Function App (dedicated Storage + shared plan)..."

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
Write-Output "> [4/7] Static Web App..."

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
Write-Output "> [5/7] Azure Container Instance (nginx)..."

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

# -- 6. Blob containers - TP Module 3 correction --------------------------------
Write-Output ""
Write-Output "> [6/7] Blob containers (private: api-logs / public: api-config)..."

$env:AZURE_STORAGE_CONNECTION_STRING = az storage account show-connection-string `
    --name           $SAName `
    --resource-group $RG `
    --query          connectionString `
    --output         tsv

# Private container - API logs (authenticated access only)
az storage container create `
    --name          "api-logs" `
    --public-access off

# Public container - API config (anonymous read access)
az storage container create `
    --name          "api-config" `
    --public-access blob

# Upload sample files
$TmpLog    = Join-Path ([System.IO.Path]::GetTempPath()) "access-log.txt"
$TmpConfig = Join-Path ([System.IO.Path]::GetTempPath()) "config.json"

"2024-06-18 09:12:33 - GET /api/hello - 200 OK - 45ms" | Set-Content -Path $TmpLog -Encoding UTF8
az storage blob upload `
    --container-name "api-logs" `
    --file           $TmpLog `
    --name           "access-log.txt" `
    --overwrite

'{"app":"AzureTech","version":"1.0","endpoints":["/api/hello","/api/status"]}' | Set-Content -Path $TmpConfig -Encoding UTF8
az storage blob upload `
    --container-name "api-config" `
    --file           $TmpConfig `
    --name           "config.json" `
    --content-type   "application/json" `
    --overwrite

$ConfigUrl = az storage blob url `
    --container-name "api-config" `
    --name           "config.json" `
    --output         tsv

Write-Output "[OK] Containers created: api-logs (private) / api-config (public)"
Write-Output "     config.json public URL: $ConfigUrl"

# -- 7. Network - VNet + Subnets + NSG - TP Module 4 correction ----------------
Write-Output ""
Write-Output "> [7/7] Network (VNet + subnets + NSG)..."

# Main VNet
az network vnet create `
    --name           $VnetName `
    --resource-group $RG `
    --location       $Location `
    --address-prefix "10.0.0.0/16" `
    --tags           @Tags

# Frontend subnet (App Service, ACI...)
az network vnet subnet create `
    --name           "subnet-frontend" `
    --vnet-name      $VnetName `
    --resource-group $RG `
    --address-prefix "10.0.1.0/24"

# Backend subnet (databases, internal services...)
az network vnet subnet create `
    --name           "subnet-backend" `
    --vnet-name      $VnetName `
    --resource-group $RG `
    --address-prefix "10.0.2.0/24"

Write-Output "[OK] VNet created: $VnetName (frontend: 10.0.1.0/24 / backend: 10.0.2.0/24)"

# NSG for subnet-frontend
az network nsg create `
    --name           $NsgName `
    --resource-group $RG `
    --location       $Location `
    --tags           @Tags

# Allow HTTP (port 80)
az network nsg rule create `
    --name                    "Allow-HTTP" `
    --nsg-name                $NsgName `
    --resource-group          $RG `
    --priority                100 `
    --direction               Inbound `
    --access                  Allow `
    --protocol                Tcp `
    --source-address-prefix   "*" `
    --source-port-range       "*" `
    --destination-address-prefix "*" `
    --destination-port-range  "80"

# Allow HTTPS (port 443)
az network nsg rule create `
    --name                    "Allow-HTTPS" `
    --nsg-name                $NsgName `
    --resource-group          $RG `
    --priority                110 `
    --direction               Inbound `
    --access                  Allow `
    --protocol                Tcp `
    --source-address-prefix   "*" `
    --source-port-range       "*" `
    --destination-address-prefix "*" `
    --destination-port-range  "443"

# Deny all other inbound traffic (explicit - good practice)
az network nsg rule create `
    --name                    "Deny-All-Inbound" `
    --nsg-name                $NsgName `
    --resource-group          $RG `
    --priority                4000 `
    --direction               Inbound `
    --access                  Deny `
    --protocol                "*" `
    --source-address-prefix   "*" `
    --source-port-range       "*" `
    --destination-address-prefix "*" `
    --destination-port-range  "*"

# Associate NSG to subnet-frontend
az network vnet subnet update `
    --name                   "subnet-frontend" `
    --vnet-name              $VnetName `
    --resource-group         $RG `
    --network-security-group $NsgName

Write-Output "[OK] NSG created and associated to subnet-frontend (HTTP:100 / HTTPS:110 / Deny:4000)"

# -- Summary -------------------------------------------------------------------
Write-Output ""
Write-Output "----------------------------------------------------"
Write-Output "  Provisioning complete"
Write-Output ""
Write-Output "  Storage Account  : $SAName"
Write-Output "    api-logs       : private (authenticated access only)"
Write-Output "    api-config     : public -- $ConfigUrl"
Write-Output "  App Service      : https://$AppUrl"
Write-Output "  Function App     : https://$FnUrl"
Write-Output "  Static Web App   : https://$StappUrl"
Write-Output "  Container ACI    : http://$AciFqdn"
Write-Output "  VNet             : $VnetName (10.0.0.0/16)"
Write-Output "    subnet-frontend: 10.0.1.0/24 -- NSG: $NsgName"
Write-Output "    subnet-backend : 10.0.2.0/24"
Write-Output "----------------------------------------------------"
