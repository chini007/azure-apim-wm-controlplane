#!/usr/bin/env bash
set -euo pipefail

SUB_ID="5e72aef8-52be-4994-8cee-3eb90e246bdb"
RG="rg-apim-srini"
APP_NAME="gh-oidc-azure-apim-wm-controlplane"

echo ">> Switching to subscription $SUB_ID"
az account set --subscription "$SUB_ID"

# 0) (Optional) Show what's in the RG before deletion
if az group show -n "$RG" --query name -o tsv >/dev/null 2>&1; then
  echo ">> Resources in $RG:"
  az resource list -g "$RG" -o table || true
else
  echo ">> Resource group $RG not found (skipping resource listing)"
fi

# 1) Delete the resource group (removes APIM, Function App, Storage, App Insights if present)
if az group show -n "$RG" --query name -o tsv >/dev/null 2>&1; then
  echo ">> Deleting resource group $RG ..."
  az group delete -n "$RG" --yes --no-wait
  echo "   (Deletion is async; you can watch with: az group wait --deleted -n $RG )"
else
  echo ">> Resource group $RG already gone."
fi

# 2) Ensure we have a Microsoft Graph token (app/SP operations)
az account get-access-token --resource-type ms-graph >/dev/null || \
  az login --use-device-code --scope https://graph.microsoft.com/.default

# 3) Look up the App Registration & Service Principal
APP_OBJECT_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].id" -o tsv || true)
APP_CLIENT_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv || true)

if [[ -n "${APP_OBJECT_ID:-}" ]]; then
  echo ">> Deleting App Registration $APP_NAME (objectId=$APP_OBJECT_ID)"
  az ad app delete --id "$APP_OBJECT_ID"
else
  echo ">> App Registration $APP_NAME not found (skipping)."
fi

if [[ -n "${APP_CLIENT_ID:-}" ]]; then
  echo ">> Deleting Service Principal for clientId=$APP_CLIENT_ID (if exists)"
  az ad sp delete --id "$APP_CLIENT_ID" || echo "   (SP may not exist or already deleted)"
else
  echo ">> No clientId resolved for $APP_NAME (skipping SP delete)."
fi

echo "✅ Cleanup steps issued."
echo "   You can verify RG deletion with: az group show -n $RG"
