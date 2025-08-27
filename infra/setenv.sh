APP_NAME="gh-oidc-azure-apim-wm-controlplane"

# Object ID (directory object) of the app
APP_OBJECT_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].id" -o tsv)

# 👉 Client ID you’ll use in GitHub Actions (this is what azure/login needs)
AZURE_CLIENT_ID=$(az ad app show --id "$APP_OBJECT_ID" --query appId -o tsv)
echo "AZURE_CLIENT_ID=$AZURE_CLIENT_ID"

# Tenant ID
AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
echo "AZURE_TENANT_ID=$AZURE_TENANT_ID"

SUB_ID="5e72aef8-52be-4994-8cee-3eb90e246bdb"
SP_ID=$(az ad sp show --id "$AZURE_CLIENT_ID" --query id -o tsv)

az role assignment list \
  --assignee-object-id "$SP_ID" \
  --scope "/subscriptions/$SUB_ID" \
  -o table
