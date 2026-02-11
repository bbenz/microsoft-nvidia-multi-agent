#!/usr/bin/env bash
# ============================================================
# Deploy GPU Parse Specialist Agent to Azure Container Apps
# ============================================================
#
# Prerequisites:
#   - Azure CLI installed and logged in
#   - Docker installed
#   - An Azure Container Registry (ACR)
#
# Usage:
#   chmod +x deploy/aca_deploy.sh
#   ./deploy/aca_deploy.sh
#
# Environment variables (override defaults):
#   RESOURCE_GROUP, LOCATION, ACR_NAME, ACA_ENV_NAME,
#   ACA_APP_NAME, ACA_GPU_SKU
# ============================================================

set -euo pipefail

# ---- Configuration ----
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-multi-agent-demo}"
LOCATION="${LOCATION:-eastus2}"
ACR_NAME="${ACR_NAME:-acrmultiagentdemo}"
ACA_ENV_NAME="${ACA_ENV_NAME:-multi-agent-env}"
ACA_APP_NAME="${ACA_APP_NAME:-gpu-parse-agent}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
ACA_GPU_SKU="${ACA_GPU_SKU:-A10}"

IMAGE_FULL="${ACR_NAME}.azurecr.io/${ACA_APP_NAME}:${IMAGE_TAG}"

echo "============================================"
echo "  ACA Deployment — GPU Parse Specialist"
echo "============================================"
echo "Resource Group : ${RESOURCE_GROUP}"
echo "Location       : ${LOCATION}"
echo "ACR            : ${ACR_NAME}"
echo "Image          : ${IMAGE_FULL}"
echo "GPU SKU        : ${ACA_GPU_SKU}"
echo "============================================"

# ---- Step 1: Create resource group ----
echo "[1/6] Creating resource group..."
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output none

# ---- Step 2: Create ACR ----
echo "[2/6] Creating Azure Container Registry..."
az acr create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${ACR_NAME}" \
  --sku Standard \
  --admin-enabled true \
  --output none

# ---- Step 3: Build and push image ----
echo "[3/6] Building and pushing container image..."
az acr build \
  --registry "${ACR_NAME}" \
  --image "${ACA_APP_NAME}:${IMAGE_TAG}" \
  --file Dockerfile \
  .

# ---- Step 4: Create ACA environment ----
echo "[4/6] Creating Container Apps environment..."
az containerapp env create \
  --name "${ACA_ENV_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output none

# ---- Step 5: Deploy container app ----
echo "[5/6] Deploying container app with GPU..."

# Get ACR credentials
ACR_PASSWORD=$(az acr credential show \
  --name "${ACR_NAME}" \
  --query "passwords[0].value" -o tsv)

az containerapp create \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --environment "${ACA_ENV_NAME}" \
  --image "${IMAGE_FULL}" \
  --registry-server "${ACR_NAME}.azurecr.io" \
  --registry-username "${ACR_NAME}" \
  --registry-password "${ACR_PASSWORD}" \
  --target-port 8001 \
  --ingress external \
  --min-replicas 0 \
  --max-replicas 3 \
  --cpu 4.0 \
  --memory 8Gi \
  --env-vars \
    "NIM_ENDPOINT=secretref:nim-endpoint" \
    "NIM_API_KEY=secretref:nim-api-key" \
    "NIM_MODEL_ID=nvidia/nemotron-parse" \
    "PARSER_API_KEY=secretref:parser-api-key" \
    "OTEL_EXPORTER_OTLP_ENDPOINT=" \
    "LOG_LEVEL=INFO" \
  --output none

# NOTE: GPU allocation via workload profiles is region-dependent.
# To enable GPU, create a workload profile with GPU support:
#
#   az containerapp env workload-profile add \
#     --name "${ACA_ENV_NAME}" \
#     --resource-group "${RESOURCE_GROUP}" \
#     --workload-profile-name "gpu-profile" \
#     --workload-profile-type "NC24-A100" \
#     --min-nodes 0 \
#     --max-nodes 1
#
# Then update the app to use it:
#
#   az containerapp update \
#     --name "${ACA_APP_NAME}" \
#     --resource-group "${RESOURCE_GROUP}" \
#     --workload-profile-name "gpu-profile"

# ---- Step 6: Get URL ----
echo "[6/6] Getting application URL..."
APP_URL=$(az containerapp show \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.configuration.ingress.fqdn" -o tsv)

echo ""
echo "============================================"
echo "  Deployment Complete!"
echo "============================================"
echo "  URL:  https://${APP_URL}"
echo "  Health: https://${APP_URL}/health"
echo ""
echo "  Set secrets:"
echo "    az containerapp secret set \\"
echo "      --name ${ACA_APP_NAME} \\"
echo "      --resource-group ${RESOURCE_GROUP} \\"
echo "      --secrets nim-endpoint=<NIM_URL> \\"
echo "                nim-api-key=<NIM_KEY> \\"
echo "                parser-api-key=<API_KEY>"
echo ""
echo "  Update PARSER_URL in your .env:"
echo "    PARSER_URL=https://${APP_URL}"
echo "============================================"
