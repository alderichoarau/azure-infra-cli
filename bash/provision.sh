#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# provision.sh — Create Azure resources via az CLI
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

set -euo pipefail   # stop immediately if a command fails

# ── Variables ─────────────────────────────────────────────────────────────────
OWNER="${OWNER:-firstname-lastname}"          # injected from GitHub secret or passed as argument
RG="${RESOURCE_GROUP:-rg-${OWNER}}"           # resource group pre-created by the trainer
RG_SHARED="rg-shared-prf2026"                 # shared resource group hosting the App Service Plan
LOCATION="francecentral"

# Tags applied to all resources — used by destroy.sh
TAGS="managed_by=cli environment=tp owner=${OWNER}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Azure Provisioning — owner: ${OWNER}"
echo "  Resource Group : ${RG}"
echo "  Region         : ${LOCATION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Business Storage Account ───────────────────────────────────────────────
echo ""
echo "▶ [1/5] Storage Account..."

# Azure constraint: 3-24 chars, lowercase letters and digits only
SA_NAME="st${OWNER//-/}cli"

az storage account create \
  --name          "$SA_NAME" \
  --resource-group "$RG" \
  --location       "$LOCATION" \
  --sku            Standard_LRS \
  --kind           StorageV2 \
  --allow-blob-public-access false \
  --tags           $TAGS

echo "✅ Storage Account created: $SA_NAME"

# ── 2. App Service (Python Web App) ───────────────────────────────────────────
# Resolve the full resource ID of the shared plan (lives in a different resource group)
APP_PLAN=$(az appservice plan show \
  --name           "plan-npr-prf2026" \
  --resource-group "$RG_SHARED" \
  --query          "id" -o tsv)

echo ""
echo "▶ [2/5] App Service (Python Web App)..."

az webapp create \
  --name           "app-${OWNER}-cli" \
  --resource-group "$RG" \
  --plan           "$APP_PLAN" \
  --runtime        "PYTHON:3.11" \
  --tags           $TAGS

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
echo "▶ [3/5] Function App (dedicated Storage + shared plan)..."

# Storage account dedicated to Functions (required — separate from business storage)
SA_FN_NAME="stfn${OWNER//-/}"
TAGS_FN="$TAGS purpose=function-storage"

az storage account create \
  --name           "$SA_FN_NAME" \
  --resource-group "$RG" \
  --location       "$LOCATION" \
  --sku            Standard_LRS \
  --tags           $TAGS_FN

az functionapp create \
  --name            "fn-${OWNER}-cli" \
  --resource-group  "$RG" \
  --storage-account "$SA_FN_NAME" \
  --plan            "$APP_PLAN" \
  --runtime         python \
  --runtime-version 3.11 \
  --os-type         Linux \
  --tags            $TAGS

FN_URL=$(az functionapp show \
  --name           "fn-${OWNER}-cli" \
  --resource-group "$RG" \
  --query          "defaultHostName" -o tsv)

echo "✅ Function App created: https://${FN_URL}"

# ── 4. Static Web App ─────────────────────────────────────────────────────────
echo ""
echo "▶ [4/5] Static Web App..."

az staticwebapp create \
  --name           "stapp-${OWNER}-cli" \
  --resource-group "$RG" \
  --location       "westeurope" \
  --tags           $TAGS

# Note: Static Web App is not available in francecentral → westeurope

STAPP_URL=$(az staticwebapp show \
  --name           "stapp-${OWNER}-cli" \
  --resource-group "$RG" \
  --query          "defaultHostname" -o tsv)

echo "✅ Static Web App created: https://${STAPP_URL}"

# ── 5. Azure Container Instance (ACI) ─────────────────────────────────────────
echo ""
echo "▶ [5/5] Azure Container Instance (nginx)..."

az container create \
  --name           "aci-${OWNER}-cli" \
  --resource-group "$RG" \
  --image          "nginx:latest" \
  --cpu            0.5 \
  --memory         0.5 \
  --ports          80 \
  --ip-address     Public \
  --dns-name-label "aci-${OWNER}-cli" \
  --environment-variables OWNER="${OWNER}" ENVIRONMENT="tp" \
  --tags           $TAGS

ACI_FQDN=$(az container show \
  --name           "aci-${OWNER}-cli" \
  --resource-group "$RG" \
  --query          "ipAddress.fqdn" -o tsv)

echo "✅ Container ACI created: http://${ACI_FQDN}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Provisioning complete"
echo ""
echo "  Storage Account  : $SA_NAME"
echo "  App Service      : https://${APP_URL}"
echo "  Function App     : https://${FN_URL}"
echo "  Static Web App   : https://${STAPP_URL}"
echo "  Container ACI    : http://${ACI_FQDN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
