#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# provision.sh — Create Azure resources via az CLI
#
# Resources created:
#   1. Storage Account + Blob containers (private: api-logs / public: api-config)
#   2. App Service (Python Web App — uses shared plan plan-npr-prf2026)
#   3. Function App (dedicated Storage + Python Function App on plan-npr-prf2026)
#   4. Static Web App
#   5. Azure Container Instance (ACI)
#   6. Blob containers (api-logs private / api-config public)
#   7. Network (VNet + subnets + NSG + rules)
#
# All resources are tagged managed_by=cli for the Friday cleanup
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail   # stop immediately if a command fails

# ── Variables ─────────────────────────────────────────────────────────────────
OWNER="${OWNER:-firstname-lastname}"          # injected from GitHub secret or passed as argument
RG="${RESOURCE_GROUP:-rg-${OWNER}}"           # resource group pre-created by the trainer
RG_SHARED="${RG_SHARED:-rg-shared-prf2026}"   # shared resource group hosting the App Service Plan
APP_PLAN_NAME="${APP_PLAN_NAME:-plan-npr-prf2026}"
LOCATION="francecentral"

# Tags applied to all resources — used by destroy.sh
TAGS=(managed_by=cli environment=tp "owner=${OWNER}")

# Network resource names
VNET_NAME="vnet-${OWNER}-cli"
NSG_NAME="nsg-frontend-${OWNER}-cli"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Azure Provisioning — owner: ${OWNER}"
echo "  Resource Group : ${RG}"
echo "  Region         : ${LOCATION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Business Storage Account ───────────────────────────────────────────────
echo ""
echo "▶ [1/7] Storage Account..."

# Azure constraint: 3-24 chars, lowercase letters and digits only
SA_NAME="st${OWNER//-/}cli"

az storage account create \
  --name                    "$SA_NAME" \
  --resource-group          "$RG" \
  --location                "$LOCATION" \
  --sku                     Standard_LRS \
  --kind                    StorageV2 \
  --allow-blob-public-access true \
  --min-tls-version         TLS1_2 \
  --tags                    "${TAGS[@]}"

echo "✅ Storage Account created: $SA_NAME"

# ── 2. App Service (Python Web App) ───────────────────────────────────────────
# Resolve the full resource ID of the shared plan (lives in a different resource group)
APP_PLAN=$(az appservice plan show \
  --name           "$APP_PLAN_NAME" \
  --resource-group "$RG_SHARED" \
  --query          "id" -o tsv)

echo ""
echo "▶ [2/7] App Service (Python Web App)..."

az webapp create \
  --name           "app-${OWNER}-cli" \
  --resource-group "$RG" \
  --plan           "$APP_PLAN" \
  --runtime        "PYTHON:3.11" \
  --tags           "${TAGS[@]}"

# HTTPS only + TLS 1.2 minimum
az webapp update \
  --name           "app-${OWNER}-cli" \
  --resource-group "$RG" \
  --https-only     true

az webapp config set \
  --name            "app-${OWNER}-cli" \
  --resource-group  "$RG" \
  --min-tls-version 1.2

# Enable automatic build on deployment
az webapp config appsettings set \
  --name           "app-${OWNER}-cli" \
  --resource-group "$RG" \
  --settings       SCM_DO_BUILD_DURING_DEPLOYMENT=true ENVIRONMENT=tp

APP_URL=$(az webapp show \
  --name           "app-${OWNER}-cli" \
  --resource-group "$RG" \
  --query          "defaultHostName" -o tsv)

echo "✅ App Service created: https://${APP_URL}"

# ── 3. Python Function App ────────────────────────────────────────────────────
echo ""
echo "▶ [3/7] Function App (dedicated Storage + shared plan)..."

# Storage account dedicated to Functions (required — separate from business storage)
SA_FN_NAME="stfn${OWNER//-/}"
TAGS_FN=("${TAGS[@]}" purpose=function-storage)

az storage account create \
  --name                  "$SA_FN_NAME" \
  --resource-group        "$RG" \
  --location              "$LOCATION" \
  --sku                   Standard_LRS \
  --public-network-access Enabled \
  --min-tls-version       TLS1_2 \
  --tags                  "${TAGS_FN[@]}"

az functionapp create \
  --name            "fn-${OWNER}-cli" \
  --resource-group  "$RG" \
  --storage-account "$SA_FN_NAME" \
  --plan            "$APP_PLAN" \
  --runtime         python \
  --runtime-version 3.11 \
  --os-type         Linux \
  --tags            "${TAGS[@]}"

FN_URL=$(az functionapp show \
  --name           "fn-${OWNER}-cli" \
  --resource-group "$RG" \
  --query          "defaultHostName" -o tsv)

echo "✅ Function App created: https://${FN_URL}"

# ── 4. Static Web App ─────────────────────────────────────────────────────────
echo ""
echo "▶ [4/7] Static Web App..."

az staticwebapp create \
  --name           "stapp-${OWNER}-cli" \
  --resource-group "$RG" \
  --location       "westeurope"

# az staticwebapp create does not support --tags, so we tag the resource after creation
STAPP_ID=$(az staticwebapp show \
  --name           "stapp-${OWNER}-cli" \
  --resource-group "$RG" \
  --query          "id" -o tsv)

az tag update \
  --resource-id "$STAPP_ID" \
  --operation   Merge \
  --tags        "${TAGS[@]}"

STAPP_URL=$(az staticwebapp show \
  --name           "stapp-${OWNER}-cli" \
  --resource-group "$RG" \
  --query          "defaultHostname" -o tsv)

echo "✅ Static Web App created: https://${STAPP_URL}"

# ── 5. Azure Container Instance (ACI) ─────────────────────────────────────────
echo ""
echo "▶ [5/7] Azure Container Instance (nginx)..."

az container create \
  --name           "aci-${OWNER}-cli" \
  --resource-group "$RG" \
  --image          "nginx:latest" \
  --cpu            0.5 \
  --memory         0.5 \
  --ports          80 \
  --ip-address     Public \
  --dns-name-label "aci-${OWNER}-cli" \
  --os-type        Linux \
  --environment-variables OWNER="${OWNER}" ENVIRONMENT="tp"

# Verify the container was actually created (az container create can return 0 on Docker Hub rate limit errors)
if az container show --name "aci-${OWNER}-cli" --resource-group "$RG" &>/dev/null; then
  ACI_ID=$(az container show \
    --name           "aci-${OWNER}-cli" \
    --resource-group "$RG" \
    --query          "id" -o tsv)

  az tag update \
    --resource-id "$ACI_ID" \
    --operation   Merge \
    --tags        "${TAGS[@]}"

  ACI_FQDN=$(az container show \
    --name           "aci-${OWNER}-cli" \
    --resource-group "$RG" \
    --query          "ipAddress.fqdn" -o tsv)

  echo "✅ Container ACI created: http://${ACI_FQDN}"
else
  echo "⚠️  Container ACI creation failed (Docker Hub rate limit?) — retry manually"
  ACI_FQDN="N/A"
fi

# ── 6. Blob containers ───────────────────────────────
echo ""
echo "▶ [6/7] Blob containers (private: api-logs / public: api-config)..."

AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
  --name           "$SA_NAME" \
  --resource-group "$RG" \
  --query          connectionString \
  --output         tsv)
export AZURE_STORAGE_CONNECTION_STRING

# Private container — API logs (authenticated access only)
az storage container create \
  --name          "api-logs" \
  --public-access off

# Public container — API config (anonymous read access)
az storage container create \
  --name          "api-config" \
  --public-access blob

# Upload sample files
echo "2024-06-18 09:12:33 - GET /api/hello - 200 OK - 45ms" > /tmp/access-log.txt
az storage blob upload \
  --container-name "api-logs" \
  --file           /tmp/access-log.txt \
  --name           "access-log.txt" \
  --overwrite

echo "{\"app\":\"AzureTech\",\"version\":\"1.0\",\"endpoints\":[\"/api/hello\",\"/api/status\"]}" > /tmp/config.json
az storage blob upload \
  --container-name "api-config" \
  --file           /tmp/config.json \
  --name           "config.json" \
  --content-type   "application/json" \
  --overwrite

CONFIG_URL=$(az storage blob url \
  --container-name "api-config" \
  --name           "config.json" \
  --output         tsv)

echo "✅ Containers created: api-logs (private) / api-config (public)"
echo "   config.json public URL: $CONFIG_URL"

# ── 7. Network — VNet + Subnets + NSG ───────────────
echo ""
echo "▶ [7/7] Network (VNet + subnets + NSG)..."

# Main VNet
az network vnet create \
  --name           "$VNET_NAME" \
  --resource-group "$RG" \
  --location       "$LOCATION" \
  --address-prefix "10.0.0.0/16" \
  --tags           "${TAGS[@]}"

# Frontend subnet (App Service, ACI...)
az network vnet subnet create \
  --name           "subnet-frontend" \
  --vnet-name      "$VNET_NAME" \
  --resource-group "$RG" \
  --address-prefix "10.0.1.0/24"

# Backend subnet (databases, internal services...)
az network vnet subnet create \
  --name           "subnet-backend" \
  --vnet-name      "$VNET_NAME" \
  --resource-group "$RG" \
  --address-prefix "10.0.2.0/24"

echo "✅ VNet created: $VNET_NAME (frontend: 10.0.1.0/24 / backend: 10.0.2.0/24)"

# NSG for subnet-frontend
az network nsg create \
  --name           "$NSG_NAME" \
  --resource-group "$RG" \
  --location       "$LOCATION" \
  --tags           "${TAGS[@]}"

# Allow HTTP (port 80)
az network nsg rule create \
  --name                    "Allow-HTTP" \
  --nsg-name                "$NSG_NAME" \
  --resource-group          "$RG" \
  --priority                100 \
  --direction               Inbound \
  --access                  Allow \
  --protocol                Tcp \
  --source-address-prefix   "*" \
  --source-port-range       "*" \
  --destination-address-prefix "*" \
  --destination-port-range  "80"

# Allow HTTPS (port 443)
az network nsg rule create \
  --name                    "Allow-HTTPS" \
  --nsg-name                "$NSG_NAME" \
  --resource-group          "$RG" \
  --priority                110 \
  --direction               Inbound \
  --access                  Allow \
  --protocol                Tcp \
  --source-address-prefix   "*" \
  --source-port-range       "*" \
  --destination-address-prefix "*" \
  --destination-port-range  "443"

# Deny all other inbound traffic (explicit — good practice)
az network nsg rule create \
  --name                    "Deny-All-Inbound" \
  --nsg-name                "$NSG_NAME" \
  --resource-group          "$RG" \
  --priority                4000 \
  --direction               Inbound \
  --access                  Deny \
  --protocol                "*" \
  --source-address-prefix   "*" \
  --source-port-range       "*" \
  --destination-address-prefix "*" \
  --destination-port-range  "*"

# Associate NSG to subnet-frontend
az network vnet subnet update \
  --name                   "subnet-frontend" \
  --vnet-name              "$VNET_NAME" \
  --resource-group         "$RG" \
  --network-security-group "$NSG_NAME"

echo "✅ NSG created and associated to subnet-frontend (HTTP:100 / HTTPS:110 / Deny:4000)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Provisioning complete"
echo ""
echo "  Storage Account  : $SA_NAME"
echo "    api-logs       : private (authenticated access only)"
echo "    api-config     : public — $CONFIG_URL"
echo "  App Service      : https://${APP_URL}"
echo "  Function App     : https://${FN_URL}"
echo "  Static Web App   : https://${STAPP_URL}"
echo "  Container ACI    : http://${ACI_FQDN}"
echo "  VNet             : $VNET_NAME (10.0.0.0/16)"
echo "    subnet-frontend: 10.0.1.0/24 — NSG: $NSG_NAME"
echo "    subnet-backend : 10.0.2.0/24"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
