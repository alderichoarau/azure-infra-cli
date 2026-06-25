#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# destroy.sh — Delete Azure resources tagged managed_by=cli
#
# ⚠️  Does NOT delete the Resource Group — only CLI-managed resources
# ⚠️  Terraform resources (managed_by=terraform) are never touched
# ⚠️  App Service Plan is NOT deleted (shared plan in rg-shared-prf2026)
#
# Deletion order matters (Azure dependencies):
#   1. Apps (functionapp, webapp, container, staticwebapp)  ← child resources first
#   2. Application Insights                                 ← auto-created with Function App
#   3. Blob containers (api-logs, api-config)               ← TP Module 3 — before storage
#   4. Network (NSG disassoc → NSG → NIC → VNet)           ← TP Module 4 — before storage
#   5. Storage Accounts                                     ← last (nothing depends on them)
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

OWNER="${OWNER:-firstname-lastname}"
RG="${RESOURCE_GROUP:-rg-${OWNER}}"

SA_NAME="st${OWNER//-/}cli"
SA_FN_NAME="stfn${OWNER//-/}"
VNET_NAME="vnet-${OWNER}-cli"
NSG_NAME="nsg-frontend-${OWNER}-cli"
NIC_NAME="nic-test-${OWNER}-cli"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🗑️  Azure Cleanup — owner: ${OWNER}"
echo "  Resource Group : ${RG}"
echo "  Target tag     : managed_by=cli"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# List the resources that will be deleted before starting
echo ""
echo "Target resources (tag managed_by=cli):"
az resource list \
  --resource-group "$RG" \
  --query "[?tags.managed_by=='cli'].{Name:name, Type:type}" \
  --output table

echo ""

# ── 1. Function App ───────────────────────────────────────────────────────────
echo "▶ Deleting Function App..."
if az functionapp show --name "fn-${OWNER}-cli" --resource-group "$RG" &>/dev/null; then
  az functionapp delete \
    --name           "fn-${OWNER}-cli" \
    --resource-group "$RG"
  echo "✅ Function App deleted"
else
  echo "⏭️  Function App not found — skipped"
fi

# ── 1b. Application Insights (auto-created with Function App) ─────────────────
echo "▶ Deleting Application Insights..."
if az monitor app-insights component show --app "fn-${OWNER}-cli" --resource-group "$RG" &>/dev/null; then
  az monitor app-insights component delete \
    --app            "fn-${OWNER}-cli" \
    --resource-group "$RG"
  echo "✅ Application Insights deleted"
else
  echo "⏭️  Application Insights not found — skipped"
fi

# ── 2. Web App ────────────────────────────────────────────────────────────────
echo "▶ Deleting App Service..."
if az webapp show --name "app-${OWNER}-cli" --resource-group "$RG" &>/dev/null; then
  az webapp delete \
    --name           "app-${OWNER}-cli" \
    --resource-group "$RG"
  echo "✅ App Service deleted"
else
  echo "⏭️  App Service not found — skipped"
fi

# ── 3. Container ACI ──────────────────────────────────────────────────────────
echo "▶ Deleting Container ACI..."
if az container show --name "aci-${OWNER}-cli" --resource-group "$RG" &>/dev/null; then
  az container delete \
    --name           "aci-${OWNER}-cli" \
    --resource-group "$RG" \
    --yes
  echo "✅ Container ACI deleted"
else
  echo "⏭️  Container ACI not found — skipped"
fi

# ── 4. Static Web App ─────────────────────────────────────────────────────────
echo "▶ Deleting Static Web App..."
if az staticwebapp show --name "stapp-${OWNER}-cli" --resource-group "$RG" &>/dev/null; then
  az staticwebapp delete \
    --name           "stapp-${OWNER}-cli" \
    --resource-group "$RG" \
    --yes
  echo "✅ Static Web App deleted"
else
  echo "⏭️  Static Web App not found — skipped"
fi

# ── 5. Blob containers — TP Module 3 correction ───────────────────────────────
# Must be done before deleting the storage account
echo "▶ Deleting Blob containers..."
if az storage account show --name "$SA_NAME" --resource-group "$RG" &>/dev/null; then
  AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
    --name           "$SA_NAME" \
    --resource-group "$RG" \
    --query          connectionString \
    --output         tsv)
  export AZURE_STORAGE_CONNECTION_STRING

  for CONTAINER in api-logs api-config; do
    if az storage container exists --name "$CONTAINER" --query exists -o tsv 2>/dev/null | grep -q true; then
      az storage container delete --name "$CONTAINER" --timeout 30
      echo "✅ Container deleted: $CONTAINER"
    else
      echo "⏭️  Container not found: $CONTAINER — skipped"
    fi
  done
else
  echo "⏭️  Storage Account not found — containers already gone"
fi

# ── 6. Network — TP Module 4 correction ──────────────────────────────────────
# NSG must be disassociated from subnet before deletion
echo "▶ Deleting Network resources (NSG → NIC → VNet)..."

# 6a. Disassociate NSG from subnet-frontend first
if az network vnet subnet show \
    --name "subnet-frontend" --vnet-name "$VNET_NAME" \
    --resource-group "$RG" &>/dev/null; then
  NSG_ASSOC=$(az network vnet subnet show \
    --name "subnet-frontend" --vnet-name "$VNET_NAME" \
    --resource-group "$RG" \
    --query "networkSecurityGroup.id" -o tsv 2>/dev/null || echo "")
  if [ -n "$NSG_ASSOC" ] && [ "$NSG_ASSOC" != "null" ]; then
    az network vnet subnet update \
      --name "subnet-frontend" --vnet-name "$VNET_NAME" \
      --resource-group "$RG" \
      --network-security-group ""
    echo "   NSG disassociated from subnet-frontend"
  fi
fi

# 6b. Delete NSG
if az network nsg show --name "$NSG_NAME" --resource-group "$RG" &>/dev/null; then
  az network nsg delete \
    --name           "$NSG_NAME" \
    --resource-group "$RG"
  echo "✅ NSG deleted: $NSG_NAME"
else
  echo "⏭️  NSG not found — skipped"
fi

# 6c. Delete test NIC (if it exists)
if az network nic show --name "$NIC_NAME" --resource-group "$RG" &>/dev/null; then
  az network nic delete \
    --name           "$NIC_NAME" \
    --resource-group "$RG"
  echo "✅ NIC deleted: $NIC_NAME"
else
  echo "⏭️  NIC not found — skipped"
fi

# 6d. Delete VNet (also deletes all subnets)
if az network vnet show --name "$VNET_NAME" --resource-group "$RG" &>/dev/null; then
  az network vnet delete \
    --name           "$VNET_NAME" \
    --resource-group "$RG"
  echo "✅ VNet deleted: $VNET_NAME (subnets included)"
else
  echo "⏭️  VNet not found — skipped"
fi

# ── 7. Storage Accounts ───────────────────────────────────────────────────────
echo "▶ Deleting Storage Accounts..."

if az storage account show --name "$SA_FN_NAME" --resource-group "$RG" &>/dev/null; then
  az storage account delete \
    --name           "$SA_FN_NAME" \
    --resource-group "$RG" \
    --yes
  echo "✅ Function Storage Account deleted: $SA_FN_NAME"
else
  echo "⏭️  $SA_FN_NAME not found — skipped"
fi

if az storage account show --name "$SA_NAME" --resource-group "$RG" &>/dev/null; then
  az storage account delete \
    --name           "$SA_NAME" \
    --resource-group "$RG" \
    --yes
  echo "✅ Business Storage Account deleted: $SA_NAME"
else
  echo "⏭️  $SA_NAME not found — skipped"
fi

# ── Final check ───────────────────────────────────────────────────────────────
echo ""
echo "Remaining resources with tag managed_by=cli:"
REMAINING=$(az resource list \
  --resource-group "$RG" \
  --query "length([?tags.managed_by=='cli'])")

if [ "$REMAINING" -eq "0" ]; then
  echo "✅ No CLI resources remaining"
else
  echo "⚠️  ${REMAINING} resource(s) not deleted — check manually"
  az resource list \
    --resource-group "$RG" \
    --query "[?tags.managed_by=='cli'].{Name:name, Type:type}" \
    --output table
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Cleanup complete — Resource Group preserved"
echo "  App Service Plan preserved (shared — rg-shared-prf2026)"
echo "  Terraform resources were not affected"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
