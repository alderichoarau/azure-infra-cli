#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# destroy.sh — Delete Azure resources tagged managed_by=cli
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

set -euo pipefail

OWNER="${OWNER:-firstname-lastname}"
RG="${RESOURCE_GROUP:-rg-${OWNER}}"

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
  --tag managed_by=cli \
  --query "[].{Name:name, Type:type}" \
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

# ── 5. Storage Accounts ───────────────────────────────────────────────────────
echo "▶ Deleting Storage Accounts..."

SA_NAME="st${OWNER//-/}cli"
if az storage account show --name "$SA_NAME" --resource-group "$RG" &>/dev/null; then
  az storage account delete \
    --name           "$SA_NAME" \
    --resource-group "$RG" \
    --yes
  echo "✅ Storage Account deleted: $SA_NAME"
else
  echo "⏭️  $SA_NAME not found — skipped"
fi

SA_FN_NAME="stfn${OWNER//-/}"
if az storage account show --name "$SA_FN_NAME" --resource-group "$RG" &>/dev/null; then
  az storage account delete \
    --name           "$SA_FN_NAME" \
    --resource-group "$RG" \
    --yes
  echo "✅ Function Storage Account deleted: $SA_FN_NAME"
else
  echo "⏭️  $SA_FN_NAME not found — skipped"
fi

# ── Final check ───────────────────────────────────────────────────────────────
echo ""
echo "Remaining resources with tag managed_by=cli:"
REMAINING=$(az resource list \
  --resource-group "$RG" \
  --tag managed_by=cli \
  --query "length(@)")

if [ "$REMAINING" -eq "0" ]; then
  echo "✅ No CLI resources remaining"
else
  echo "⚠️  ${REMAINING} resource(s) not deleted — check manually"
  az resource list \
    --resource-group "$RG" \
    --tag managed_by=cli \
    --query "[].{Name:name, Type:type}" \
    --output table
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Cleanup complete — Resource Group preserved"
echo "  Terraform resources were not affected"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
