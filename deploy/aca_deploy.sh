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
#   ACA_APP_NAME, ACA_WORKLOAD_PROFILE_TYPE, ACA_WORKLOAD_PROFILE_NAME
# ============================================================

set -euo pipefail

# ---- Configuration ----
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-multi-agent-demo}"
LOCATION="${LOCATION:-eastus2}"
ACR_NAME="${ACR_NAME:-acrmultiagentdemo}"
ACA_ENV_NAME="${ACA_ENV_NAME:-multi-agent-env}"
ACA_APP_NAME="${ACA_APP_NAME:-gpu-parse-agent}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
ACA_WORKLOAD_PROFILE_NAME="${ACA_WORKLOAD_PROFILE_NAME:-gpu-profile}"
ACA_WORKLOAD_PROFILE_TYPE="${ACA_WORKLOAD_PROFILE_TYPE:-}"

IMAGE_FULL="${ACR_NAME}.azurecr.io/${ACA_APP_NAME}:${IMAGE_TAG}"

echo "============================================"
echo "  ACA Deployment — GPU Parse Specialist"
echo "============================================"
echo "Resource Group : ${RESOURCE_GROUP}"
echo "Location       : ${LOCATION}"
echo "ACR            : ${ACR_NAME}"
echo "Image          : ${IMAGE_FULL}"
echo "GPU Profile    : ${ACA_WORKLOAD_PROFILE_NAME}"
echo "============================================"

# Query and interactively select a GPU workload profile for the target region.
# If ACA_WORKLOAD_PROFILE_TYPE is already set (env var), selection is skipped.
select_gpu_workload_profile() {
  local location="$1"

  echo "Querying available GPU workload profiles in ${location}..."
  local all_profiles
  all_profiles=$(az containerapp env workload-profile list-supported \
    --location "${location}" \
    --query "[].name" \
    --output tsv)

  # Filter to GPU profiles only (strip \r from Windows az CLI output)
  local gpu_profiles=()
  while IFS= read -r line; do
    line="${line//$'\r'/}"
    [[ -n "${line}" ]] && gpu_profiles+=("${line}")
  done < <(grep "GPU" <<< "${all_profiles}" || true)

  if [[ ${#gpu_profiles[@]} -eq 0 ]]; then
    echo "ERROR: No GPU workload profiles available in ${location}."
    echo "Choose another region or set ACA_WORKLOAD_PROFILE_TYPE explicitly."
    exit 1
  fi

  # Find default (prefer T4, then first available)
  local default_idx=0
  for i in "${!gpu_profiles[@]}"; do
    if [[ "${gpu_profiles[$i]}" == *T4* ]]; then
      default_idx=$i
      break
    fi
  done

  echo ""
  echo "Available GPU workload profiles in ${location}:"
  echo "--------------------------------------------"
  for i in "${!gpu_profiles[@]}"; do
    local marker=""
    [[ $i -eq $default_idx ]] && marker=" (default)"
    echo "  $((i + 1)). ${gpu_profiles[$i]}${marker}"
  done
  echo ""

  local choice
  read -r -p "Select GPU profile [1-${#gpu_profiles[@]}] (press Enter for default): " choice

  if [[ -z "${choice}" ]]; then
    choice=$((default_idx + 1))
  fi

  if ! [[ "${choice}" =~ ^[0-9]+$ ]] || [[ ${choice} -lt 1 ]] || [[ ${choice} -gt ${#gpu_profiles[@]} ]]; then
    echo "Invalid selection: ${choice}"
    exit 1
  fi

  ACA_WORKLOAD_PROFILE_TYPE="${gpu_profiles[$((choice - 1))]}"
  echo "Selected: ${ACA_WORKLOAD_PROFILE_TYPE}"
  echo ""
}

# ---- Step 0: Preflight checks ----
echo "[0/7] Running Azure CLI preflight checks..."

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI (az) is not installed or not on PATH."
  exit 1
fi

if ! az account show --output none >/dev/null 2>&1; then
  echo "Azure CLI is not authenticated. Run: az login"
  exit 1
fi

echo "Ensuring Container Apps CLI extension is installed and up to date..."
az extension add \
  --name containerapp \
  --upgrade \
  --only-show-errors \
  --output none

echo "Ensuring required resource providers are registered..."
az provider register --namespace Microsoft.App --wait --output none
az provider register --namespace Microsoft.OperationalInsights --wait --output none

# ---- GPU profile selection ----
if [[ -z "${ACA_WORKLOAD_PROFILE_TYPE}" ]]; then
  select_gpu_workload_profile "${LOCATION}"
else
  echo "Using pre-set GPU profile type: ${ACA_WORKLOAD_PROFILE_TYPE}"
fi

# ---- Step 1: Create resource group ----
echo "[1/7] Creating resource group..."
if az group show --name "${RESOURCE_GROUP}" --output none >/dev/null 2>&1; then
  echo "Resource group ${RESOURCE_GROUP} already exists. Reusing it."
else
  az group create \
    --name "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --output none
fi

# ---- Step 2: Create ACR ----
echo "[2/7] Creating Azure Container Registry..."
if az acr show --name "${ACR_NAME}" --output none >/dev/null 2>&1; then
  echo "ACR ${ACR_NAME} already exists. Reusing it."

  ACR_RESOURCE_GROUP=$(az acr show --name "${ACR_NAME}" --query "resourceGroup" -o tsv)
  ACR_RESOURCE_GROUP="${ACR_RESOURCE_GROUP//$'\r'/}"
  if [[ "${ACR_RESOURCE_GROUP}" != "${RESOURCE_GROUP}" ]]; then
    echo "ACR ${ACR_NAME} is in resource group ${ACR_RESOURCE_GROUP}; using it anyway."
  fi

  ACR_ADMIN_ENABLED=$(az acr show --name "${ACR_NAME}" --query "adminUserEnabled" -o tsv)
  ACR_ADMIN_ENABLED="${ACR_ADMIN_ENABLED//$'\r'/}"
  if [[ "${ACR_ADMIN_ENABLED}" != "true" ]]; then
    echo "Enabling admin user on existing ACR ${ACR_NAME} for image pull credentials..."
    az acr update --name "${ACR_NAME}" --admin-enabled true --output none
  fi
else
  az acr create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${ACR_NAME}" \
    --sku Standard \
    --admin-enabled true \
    --output none
fi

# ---- Step 3: Build and push image ----
echo "[3/7] Building and pushing container image..."

BUILD_CONTEXT_DIR="${PWD}/.aca-build-context"
rm -rf "${BUILD_CONTEXT_DIR}"
mkdir -p "${BUILD_CONTEXT_DIR}"
cleanup_build_context() {
  rm -rf "${BUILD_CONTEXT_DIR}"
}
trap cleanup_build_context EXIT

echo "Preparing sanitized build context (excluding local environment artifacts)..."
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git archive --format=tar HEAD | tar -C "${BUILD_CONTEXT_DIR}" -xf -
else
  tar \
    --exclude='.git' \
    --exclude='.venv' \
    --exclude='.vscode' \
    --exclude='__pycache__' \
    --exclude='.pytest_cache' \
    --exclude='.mypy_cache' \
    --exclude='*.pyc' \
    --exclude='*.pyo' \
    -cf - . | tar -C "${BUILD_CONTEXT_DIR}" -xf -
fi

BUILD_CONTEXT_ARG="${BUILD_CONTEXT_DIR}"
AZ_PATH=$(command -v az || true)
# Detect Windows az CLI running under WSL (path starts with /mnt/)
if [[ -n "${AZ_PATH}" && "${AZ_PATH}" == /mnt/* ]] && command -v wslpath >/dev/null 2>&1; then
  BUILD_CONTEXT_ARG=$(wslpath -w "${BUILD_CONTEXT_DIR}")
  echo "Detected Windows Azure CLI; converted build context to: ${BUILD_CONTEXT_ARG}"
fi

az acr build \
  --registry "${ACR_NAME}" \
  --image "${ACA_APP_NAME}:${IMAGE_TAG}" \
  --file Dockerfile \
  "${BUILD_CONTEXT_ARG}"

rm -rf "${BUILD_CONTEXT_DIR}"
trap - EXIT

# ---- Step 4: Create ACA environment ----
echo "[4/7] Creating Container Apps environment..."
if az containerapp env show \
  --name "${ACA_ENV_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --output none >/dev/null 2>&1; then
  echo "Container Apps environment ${ACA_ENV_NAME} already exists. Reusing it."
else
  az containerapp env create \
    --name "${ACA_ENV_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --output none
fi

echo "GPU Profile Type: ${ACA_WORKLOAD_PROFILE_TYPE}"

# Ensure GPU workload profile exists in the environment
EXISTING_PROFILE_TYPE=$(az containerapp env workload-profile list \
  --name "${ACA_ENV_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?name=='${ACA_WORKLOAD_PROFILE_NAME}'].properties.workloadProfileType | [0]" \
  --output tsv || true)
EXISTING_PROFILE_TYPE="${EXISTING_PROFILE_TYPE//$'\r'/}"

if [[ -z "${EXISTING_PROFILE_TYPE}" ]]; then
  echo "Adding GPU workload profile ${ACA_WORKLOAD_PROFILE_NAME}..."
  ADD_ARGS=(
    --name "${ACA_ENV_NAME}"
    --resource-group "${RESOURCE_GROUP}"
    --workload-profile-name "${ACA_WORKLOAD_PROFILE_NAME}"
    --workload-profile-type "${ACA_WORKLOAD_PROFILE_TYPE}"
    --output none
  )
  # Consumption GPU profiles don't support min/max node counts
  if [[ "${ACA_WORKLOAD_PROFILE_TYPE}" != Consumption-GPU-* ]]; then
    ADD_ARGS+=(--min-nodes 0 --max-nodes 1)
  fi
  az containerapp env workload-profile add "${ADD_ARGS[@]}"
elif [[ "${EXISTING_PROFILE_TYPE}" != "${ACA_WORKLOAD_PROFILE_TYPE}" ]]; then
  echo "Workload profile ${ACA_WORKLOAD_PROFILE_NAME} exists with type ${EXISTING_PROFILE_TYPE}."
  echo "Requested type is ${ACA_WORKLOAD_PROFILE_TYPE}. Use a different ACA_WORKLOAD_PROFILE_NAME or recreate the environment."
  exit 1
else
  echo "GPU workload profile ${ACA_WORKLOAD_PROFILE_NAME} already exists."
fi

# ---- Step 5: Deploy container app ----
echo "[5/7] Deploying container app with GPU..."

# Get ACR credentials (strip \r from Windows az CLI output)
ACR_PASSWORD=$(az acr credential show \
  --name "${ACR_NAME}" \
  --query "passwords[0].value" -o tsv)
ACR_PASSWORD="${ACR_PASSWORD//$'\r'/}"

APP_EXISTS=false
APP_STATE=""
if az containerapp show \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --output none >/dev/null 2>&1; then
  APP_STATE=$(az containerapp show \
    --name "${ACA_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "properties.provisioningState" -o tsv 2>/dev/null || true)
  APP_STATE="${APP_STATE//$'\r'/}"
  if [[ "${APP_STATE}" == "Failed" ]]; then
    echo "Container app ${ACA_APP_NAME} is in Failed state. Deleting and recreating..."
    az containerapp delete \
      --name "${ACA_APP_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --yes --output none
  else
    APP_EXISTS=true
  fi
fi

if [[ "${APP_EXISTS}" == "true" ]]; then
  echo "Container app ${ACA_APP_NAME} already exists. Updating it."
  az containerapp secret set \
    --name "${ACA_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --secrets \
      "nim-endpoint=placeholder" \
      "nim-api-key=placeholder" \
      "parser-api-key=placeholder" \
    --output none 2>/dev/null || true
  az containerapp registry set \
    --name "${ACA_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --server "${ACR_NAME}.azurecr.io" \
    --username "${ACR_NAME}" \
    --password "${ACR_PASSWORD}" \
    --output none
  az containerapp update \
    --name "${ACA_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --workload-profile-name "${ACA_WORKLOAD_PROFILE_NAME}" \
    --image "${IMAGE_FULL}" \
    --target-port 8001 \
    --ingress external \
    --min-replicas 0 \
    --max-replicas 3 \
    --cpu 4.0 \
    --memory 8Gi \
    --set-env-vars \
      "NIM_ENDPOINT=secretref:nim-endpoint" \
      "NIM_API_KEY=secretref:nim-api-key" \
      "NIM_MODEL_ID=nvidia/nemotron-parse" \
      "PARSER_API_KEY=secretref:parser-api-key" \
      "OTEL_EXPORTER_OTLP_ENDPOINT=" \
      "LOG_LEVEL=INFO" \
    --output none
else
  az containerapp create \
    --name "${ACA_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --environment "${ACA_ENV_NAME}" \
    --workload-profile-name "${ACA_WORKLOAD_PROFILE_NAME}" \
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
    --secrets \
      "nim-endpoint=placeholder" \
      "nim-api-key=placeholder" \
      "parser-api-key=placeholder" \
    --env-vars \
      "NIM_ENDPOINT=secretref:nim-endpoint" \
      "NIM_API_KEY=secretref:nim-api-key" \
      "NIM_MODEL_ID=nvidia/nemotron-parse" \
      "PARSER_API_KEY=secretref:parser-api-key" \
      "OTEL_EXPORTER_OTLP_ENDPOINT=" \
      "LOG_LEVEL=INFO" \
    --output none
fi

# ---- Step 6: Get URL ----
echo "[6/7] Getting application URL..."
APP_URL=$(az containerapp show \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.configuration.ingress.fqdn" -o tsv)
APP_URL="${APP_URL//$'\r'/}"

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
