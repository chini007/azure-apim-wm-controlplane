#!/usr/bin/env bash
set -euo pipefail

# ---- inputs (edit or pass as env) ----
LOCATION=${LOCATION:-westeurope}
RG=${RG:-rg-apim-srini}
APIM_NAME=${APIM_NAME:-apim-srini-consumption}
FUNC_APP=${FUNC_APP:-fa-azure-agent-srini}
STORAGE=${STORAGE:-st$RANDOM$RANDOM}
AI_NAME=${AI_NAME:-appi-srini}

# Control Plane settings (set via GitHub Encrypted Secrets in CI, or export locally)
ACP_BASE_URL=${ACP_BASE_URL:-"https://<your-control-plane-host>"}
ACP_ORG_ID=${ACP_ORG_ID:-"<acp-org-id>"}
ACP_ENV_ID=${ACP_ENV_ID:-"<acp-env-or-catalog-id>"}
ACP_RUNTIME_TYPE=${ACP_RUNTIME_TYPE:-"azure-apim"}
ACP_CLIENT_ID=${ACP_CLIENT_ID:-"<acp-client-id>"}
ACP_CLIENT_SECRET=${ACP_CLIENT_SECRET:-"<acp-client-secret>"}

echo ">> Using subscription: $(az account show --query id -o tsv)"
echo ">> Creating resource group: $RG ($LOCATION)"
az group create -n "$RG" -l "$LOCATION" >/dev/null

echo ">> Creating APIM (Consumption): $APIM_NAME"
az apim create \
  -g "$RG" -n "$APIM_NAME" -l "$LOCATION" \
  --sku-name Consumption \
  --publisher-email "srini@example.com" \
  --publisher-name "Srini" >/dev/null

echo ">> Creating Storage account for Functions: $STORAGE"
az storage account create -g "$RG" -n "$STORAGE" -l "$LOCATION" --sku Standard_LRS >/dev/null

echo ">> Creating App Insights: $AI_NAME"
az monitor app-insights component create -g "$RG" -l "$LOCATION" -a "$AI_NAME" >/devnull 2>&1 || true
AI_CONN=$(az monitor app-insights component show -g "$RG" -a "$AI_NAME" --query connectionString -o tsv)

echo ">> Creating Function App (Linux, Java 17, v4): $FUNC_APP"
az functionapp create \
  -g "$RG" -n "$FUNC_APP" -s "$STORAGE" -c "$LOCATION" \
  --functions-version 4 --os-type Linux \
  --runtime java --runtime-version 17 >/dev/null

echo ">> Enabling managed identity on Function App"
az functionapp identity assign -g "$RG" -n "$FUNC_APP" >/dev/null
FUNC_PID=$(az functionapp identity show -g "$RG" -n "$FUNC_APP" --query principalId -o tsv)
APIM_ID=$(az apim show -g "$RG" -n "$APIM_NAME" --query id -o tsv)

echo ">> Granting Reader on APIM to Function App MI"
az role assignment create \
  --assignee-object-id "$FUNC_PID" \
  --assignee-principal-type ServicePrincipal \
  --role Reader --scope "$APIM_ID" >/dev/null

echo ">> Setting Function App configuration"
az functionapp config appsettings set -g "$RG" -n "$FUNC_APP" --settings \
  "APPLICATIONINSIGHTS_CONNECTION_STRING=$AI_CONN" \
  "ACP_BASE_URL=$ACP_BASE_URL" \
  "ACP_ORG_ID=$ACP_ORG_ID" \
  "ACP_ENV_ID=$ACP_ENV_ID" \
  "ACP_RUNTIME_TYPE=$ACP_RUNTIME_TYPE" \
  "ACP_CLIENT_ID=$ACP_CLIENT_ID" \
  "ACP_CLIENT_SECRET=$ACP_CLIENT_SECRET" \
  "AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)" \
  "AZURE_RESOURCE_GROUP=$RG" \
  "AZURE_APIM_NAME=$APIM_NAME" >/dev/null

echo "✅ Infra ready: RG=$RG, APIM=$APIM_NAME, FUNC=$FUNC_APP"
