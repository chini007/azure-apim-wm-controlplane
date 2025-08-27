#!/usr/bin/env bash
set -euo pipefail

SUB_ID="b1d9e34e-aab0-4081-872b-9fdf0dd0f975"                 # <-- put your PAYG subscription ID here
APP_NAME="gh-oidc-azure-apim-wm-controlplane"
GITHUB_OWNER="chini007"
GITHUB_REPO="azure-apim-wm-controlplane"
FED_NAME="github-actions-main"
ROLE="Contributor"                     # or "Owner" if CI must assign roles later

echo ">> Switching to $SUB_ID"
az account set --subscription "$SUB_ID"

# Ensure Graph token available
az account get-access-token --resource-type ms-graph >/dev/null || \
  az login --use-device-code --scope https://graph.microsoft.com/.default

# Create app if missing
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
if [ -z "${APP_ID:-}" ]; then
  echo ">> Creating app: $APP_NAME"
  APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
else
  echo ">> App exists: $APP_ID"
fi

# Ensure service principal exists
az ad sp create --id "$APP_ID" --only-show-errors || true
SP_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)

# Federated credential for GitHub Actions (main)
EXISTS=$(az ad app federated-credential list --id "$APP_ID" \
  --query "[?name=='$FED_NAME'] | length(@)")
[ "$EXISTS" = "0" ] && az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\": \"$FED_NAME\",
  \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"repo:$GITHUB_OWNER/$GITHUB_REPO:ref:refs/heads/main\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}"

# Grant RBAC on the subscription (or change scope to an RG)
az role assignment create \
  --assignee-object-id "$SP_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "$ROLE" \
  --scope "/subscriptions/$SUB_ID" || echo "(role may already be assigned)"

echo "AZURE_CLIENT_ID=$APP_ID"
echo "AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID=$SUB_ID"
