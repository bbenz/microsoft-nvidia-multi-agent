#!/usr/bin/env bash
# ============================================================
# Deploy Azure AI Foundry Hub, Project & GPT-4o Model
# ============================================================
#
# Covers Steps 1-4 from docs/deploying_models_foundry.md:
#   1. Create an Azure AI Foundry Hub
#   2. Create an Azure AI Foundry Project
#   3. Deploy a GPT-4o Model
#   4. Configure the Orchestrator (.env)
#
# For Step 5 (NIM), it configures NVIDIA API Catalog (Option A).
#
# Prerequisites:
#   - Azure CLI installed and logged in
#   - Azure subscription with Azure OpenAI access
#
# Usage:
#   chmod +x deploy/foundry_deploy.sh
#   ./deploy/foundry_deploy.sh
#
# Environment variables (override defaults):
#   RESOURCE_GROUP, LOCATION, HUB_NAME, PROJECT_NAME,
#   OPENAI_RESOURCE_NAME, OPENAI_DEPLOYMENT_NAME, OPENAI_MODEL_NAME,
#   OPENAI_MODEL_VERSION, OPENAI_SKU_CAPACITY
# ============================================================

set -euo pipefail

# ---- Helpers: strip \r from Windows az CLI output ----
strip_cr() { tr -d '\r'; }

# ---- Configuration ----
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-multi-agent-demo}"
LOCATION="${LOCATION:-eastus2}"
HUB_NAME="${HUB_NAME:-multi-agent-hub}"
PROJECT_NAME="${PROJECT_NAME:-multi-agent-project}"
OPENAI_RESOURCE_NAME="${OPENAI_RESOURCE_NAME:-multi-agent-openai}"
OPENAI_DEPLOYMENT_NAME="${OPENAI_DEPLOYMENT_NAME:-gpt-4o}"
OPENAI_MODEL_NAME="${OPENAI_MODEL_NAME:-gpt-4o}"
OPENAI_MODEL_VERSION="${OPENAI_MODEL_VERSION:-2024-11-20}"
OPENAI_SKU_CAPACITY="${OPENAI_SKU_CAPACITY:-50}"
ENV_FILE="${ENV_FILE:-.env}"

echo "============================================"
echo "  Azure AI Foundry Deployment"
echo "============================================"
echo "Resource Group  : ${RESOURCE_GROUP}"
echo "Location        : ${LOCATION}"
echo "Hub             : ${HUB_NAME}"
echo "Project         : ${PROJECT_NAME}"
echo "OpenAI Resource : ${OPENAI_RESOURCE_NAME}"
echo "Model           : ${OPENAI_MODEL_NAME} (${OPENAI_MODEL_VERSION})"
echo "Deployment      : ${OPENAI_DEPLOYMENT_NAME}"
echo "============================================"

# ---- Step 0: Preflight checks ----
echo ""
echo "[0/5] Running Azure CLI preflight checks..."

if ! command -v az >/dev/null 2>&1; then
  echo "ERROR: Azure CLI (az) is not installed or not on PATH."
  exit 1
fi

if ! az account show --output none >/dev/null 2>&1; then
  echo "ERROR: Azure CLI is not authenticated. Run: az login"
  exit 1
fi

echo "Ensuring ml extension is installed..."
az extension add --name ml --upgrade --only-show-errors --output none 2>/dev/null || true

echo "Ensuring required resource providers are registered..."
az provider register --namespace Microsoft.MachineLearningServices --wait --output none
az provider register --namespace Microsoft.CognitiveServices --wait --output none

# ---- Step 1: Create resource group ----
echo ""
echo "[1/5] Creating resource group..."
if az group show --name "${RESOURCE_GROUP}" --output none >/dev/null 2>&1; then
  echo "Resource group ${RESOURCE_GROUP} already exists. Reusing it."
else
  az group create \
    --name "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --output none
fi

# ---- Step 2: Create Azure OpenAI resource & deploy GPT-4o ----
echo ""
echo "[2/5] Creating Azure OpenAI resource..."
if az cognitiveservices account show \
  --name "${OPENAI_RESOURCE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --output none >/dev/null 2>&1; then
  echo "OpenAI resource ${OPENAI_RESOURCE_NAME} already exists. Reusing it."
else
  az cognitiveservices account create \
    --name "${OPENAI_RESOURCE_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --kind OpenAI \
    --sku S0 \
    --location "${LOCATION}" \
    --output none
fi

echo ""
echo "[3/5] Deploying ${OPENAI_MODEL_NAME} model..."
EXISTING_DEPLOYMENT=$(az cognitiveservices account deployment list \
  --name "${OPENAI_RESOURCE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?name=='${OPENAI_DEPLOYMENT_NAME}'].name | [0]" \
  --output tsv 2>/dev/null | strip_cr || true)

if [[ -n "${EXISTING_DEPLOYMENT}" ]]; then
  echo "Deployment ${OPENAI_DEPLOYMENT_NAME} already exists. Reusing it."
else
  az cognitiveservices account deployment create \
    --name "${OPENAI_RESOURCE_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --deployment-name "${OPENAI_DEPLOYMENT_NAME}" \
    --model-name "${OPENAI_MODEL_NAME}" \
    --model-version "${OPENAI_MODEL_VERSION}" \
    --model-format OpenAI \
    --sku-capacity "${OPENAI_SKU_CAPACITY}" \
    --sku-name Standard \
    --output none
fi

# ---- Step 3: Create AI Foundry Hub ----
echo ""
echo "[4/5] Creating Azure AI Foundry Hub & Project..."

EXISTING_HUB=$(az ml workspace show \
  --name "${HUB_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "name" -o tsv 2>/dev/null | strip_cr || true)

if [[ -n "${EXISTING_HUB}" ]]; then
  echo "Hub ${HUB_NAME} already exists. Reusing it."
else
  az ml workspace create \
    --name "${HUB_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --kind hub \
    --location "${LOCATION}" \
    --output none
fi

# Get hub resource ID for project creation
HUB_ID=$(az ml workspace show \
  --name "${HUB_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "id" -o tsv | strip_cr)

# Create project
EXISTING_PROJECT=$(az ml workspace show \
  --name "${PROJECT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "name" -o tsv 2>/dev/null | strip_cr || true)

if [[ -n "${EXISTING_PROJECT}" ]]; then
  echo "Project ${PROJECT_NAME} already exists. Reusing it."
else
  az ml workspace create \
    --name "${PROJECT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --kind project \
    --hub-id "${HUB_ID}" \
    --output none
fi

# ---- Step 4: Write .env configuration ----
echo ""
echo "[5/5] Configuring .env file..."

OPENAI_ENDPOINT=$(az cognitiveservices account show \
  --name "${OPENAI_RESOURCE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.endpoint" -o tsv | strip_cr)

OPENAI_KEY=$(az cognitiveservices account keys list \
  --name "${OPENAI_RESOURCE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "key1" -o tsv | strip_cr)

# Build .env content
# Preserve existing NIM and other settings if .env already exists
write_env_var() {
  local key="$1" value="$2" file="$3"
  if [[ -f "${file}" ]] && grep -q "^${key}=" "${file}" 2>/dev/null; then
    # Update existing key (portable sed)
    if sed --version >/dev/null 2>&1; then
      sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
    else
      sed -i '' "s|^${key}=.*|${key}=${value}|" "${file}"
    fi
  else
    echo "${key}=${value}" >> "${file}"
  fi
}

# Create .env from .env.example if it doesn't exist
if [[ ! -f "${ENV_FILE}" ]] && [[ -f ".env.example" ]]; then
  cp .env.example "${ENV_FILE}"
  echo "Created ${ENV_FILE} from .env.example"
fi
touch "${ENV_FILE}"

write_env_var "OPENAI_API_KEY" "${OPENAI_KEY}" "${ENV_FILE}"
write_env_var "OPENAI_MODEL" "${OPENAI_DEPLOYMENT_NAME}" "${ENV_FILE}"
write_env_var "OPENAI_API_BASE" "${OPENAI_ENDPOINT}" "${ENV_FILE}"
write_env_var "OPENAI_API_VERSION" "2025-03-01-preview" "${ENV_FILE}"
write_env_var "OPENAI_API_TYPE" "azure" "${ENV_FILE}"

echo ""
echo "============================================"
echo "  Foundry Deployment Complete!"
echo "============================================"
echo "  OpenAI Endpoint : ${OPENAI_ENDPOINT}"
echo "  Deployment      : ${OPENAI_DEPLOYMENT_NAME}"
echo "  Hub             : ${HUB_NAME}"
echo "  Project         : ${PROJECT_NAME}"
echo ""
echo "  .env updated with Azure OpenAI credentials."
echo ""
echo "  For NIM (Step 5 - NVIDIA API Catalog), add to .env:"
echo "    NIM_ENDPOINT=https://integrate.api.nvidia.com/v1"
echo "    NIM_MODEL_ID=nvidia/nemotron-parse"
echo "    NIM_API_KEY=nvapi-your-key-here"
echo ""
echo "  Get your NVIDIA API key at: https://build.nvidia.com"
echo "============================================"
