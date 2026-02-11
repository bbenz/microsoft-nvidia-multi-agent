# Deploying to Azure Container Apps (ACA)

This guide provides complete, step-by-step instructions for deploying the **GPU Parse Specialist Agent** to Azure Container Apps with optional NVIDIA GPU support.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture on ACA](#architecture-on-aca)
4. [Step 1: Prepare the Environment](#step-1-prepare-the-environment)
5. [Step 2: Build the Container Image](#step-2-build-the-container-image)
6. [Step 3: Create the ACA Environment](#step-3-create-the-aca-environment)
7. [Step 4: Deploy the Parser Service](#step-4-deploy-the-parser-service)
8. [Step 5: Configure Secrets](#step-5-configure-secrets)
9. [Step 6: Add GPU Workload Profile (Optional)](#step-6-add-gpu-workload-profile-optional)
10. [Step 7: Configure Custom Domain and TLS (Optional)](#step-7-configure-custom-domain-and-tls-optional)
11. [Step 8: Connect the Orchestrator](#step-8-connect-the-orchestrator)
12. [Automated Deployment Script](#automated-deployment-script)
13. [Monitoring and Observability](#monitoring-and-observability)
14. [Scaling Configuration](#scaling-configuration)
15. [Cost Management](#cost-management)
16. [CI/CD with GitHub Actions](#cicd-with-github-actions)
17. [Troubleshooting](#troubleshooting)

---

## Overview

The deployment architecture places the **GPU Parse Specialist** on Azure Container Apps, which provides:

- **Serverless containers** — no VM management
- **Scale-to-zero** — pay only when processing requests
- **GPU workload profiles** — NVIDIA A10 or A100 GPUs on demand
- **Built-in ingress** — HTTPS endpoints with automatic TLS
- **Managed identity** — secure access to Azure services

The **Coordinator Agent** (orchestrator) runs locally or in any compute environment and calls the parser service over HTTPS.

---

## Prerequisites

### Required Tools

```bash
# Azure CLI (2.60+)
az --version

# Docker (for local testing)
docker --version

# Verify Azure login
az login
az account show
```

### Required Azure Permissions

- **Contributor** on the resource group
- **AcrPush** on the container registry
- Access to create Container Apps environments

### Verify Provider Registration

```bash
# Register the Container Apps resource provider (one-time)
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.OperationalInsights --wait
```

---

## Architecture on ACA

```
Internet
    │
    ▼
┌──────────────────────────────────────┐
│  Azure Container Apps Environment    │
│                                      │
│  ┌──────────────────────────────┐    │
│  │  gpu-parse-agent             │    │
│  │  ┌────────────────────────┐  │    │
│  │  │  FastAPI (port 8001)   │  │    │
│  │  │  ├─ POST /parse        │  │    │
│  │  │  └─ GET  /health       │  │    │
│  │  └────────────────────────┘  │    │
│  │  CPU: 4 cores / RAM: 8 GiB  │    │
│  │  GPU: NVIDIA A10 (optional) │    │
│  │  Scale: 0-3 replicas        │    │
│  └──────────────────────────────┘    │
│                                      │
│  ┌──────────────────────────────┐    │
│  │  Secrets                     │    │
│  │  ├─ nim-endpoint             │    │
│  │  ├─ nim-api-key              │    │
│  │  └─ parser-api-key           │    │
│  └──────────────────────────────┘    │
└──────────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────────┐
│  Azure Container Registry (ACR)      │
│  acrmultiagentdemo.azurecr.io        │
└──────────────────────────────────────┘
```

---

## Step 1: Prepare the Environment

Set your deployment variables. Customize these as needed:

```bash
# Configuration (edit these values)
export RESOURCE_GROUP="rg-multi-agent-demo"
export LOCATION="eastus2"
export ACR_NAME="acrmultiagentdemo"      # Must be globally unique
export ACA_ENV_NAME="multi-agent-env"
export ACA_APP_NAME="gpu-parse-agent"
export IMAGE_TAG="latest"

# Derived
export IMAGE_FULL="${ACR_NAME}.azurecr.io/${ACA_APP_NAME}:${IMAGE_TAG}"
```

### Create the Resource Group

```bash
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}"
```

### Create the Container Registry

```bash
az acr create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${ACR_NAME}" \
  --sku Standard \
  --admin-enabled true
```

> **Tip:** For production, use **Premium** SKU with managed identity authentication instead of admin credentials.

---

## Step 2: Build the Container Image

### Option A: Build in Azure (Recommended)

No local Docker required — ACR builds the image in the cloud:

```bash
# From the project root directory
az acr build \
  --registry "${ACR_NAME}" \
  --image "${ACA_APP_NAME}:${IMAGE_TAG}" \
  --file Dockerfile \
  .
```

### Option B: Build Locally and Push

```bash
# Build
docker build -t "${IMAGE_FULL}" -f Dockerfile .

# Login to ACR
az acr login --name "${ACR_NAME}"

# Push
docker push "${IMAGE_FULL}"
```

### Option C: Test Locally First

```bash
# Build and run locally
docker build -t gpu-parse-agent:local -f Dockerfile .

docker run -p 8001:8001 \
  -e PARSER_API_KEY=demo-api-key-change-me \
  -e LOG_LEVEL=DEBUG \
  gpu-parse-agent:local

# Test the health endpoint
curl http://localhost:8001/health

# Test a parse request
curl -X POST http://localhost:8001/parse \
  -H "Content-Type: application/json" \
  -H "X-API-Key: demo-api-key-change-me" \
  -d '{"pdf_url": "http://example.com/invoice.pdf"}'
```

---

## Step 3: Create the ACA Environment

```bash
az containerapp env create \
  --name "${ACA_ENV_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}"
```

This creates a Container Apps environment with a **Consumption** workload profile (CPU-only). GPU support is added in [Step 6](#step-6-add-gpu-workload-profile-optional).

### Verify Environment Status

```bash
az containerapp env show \
  --name "${ACA_ENV_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.provisioningState" -o tsv
# Expected: Succeeded
```

---

## Step 4: Deploy the Parser Service

### Get ACR Credentials

```bash
ACR_PASSWORD=$(az acr credential show \
  --name "${ACR_NAME}" \
  --query "passwords[0].value" -o tsv)
```

### Deploy

```bash
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
    "NIM_MODEL_ID=nvidia/nemotron-parse" \
    "OTEL_EXPORTER_OTLP_ENDPOINT=" \
    "LOG_LEVEL=INFO" \
  --query "properties.configuration.ingress.fqdn" -o tsv
```

The command outputs the FQDN of your deployed app (e.g., `gpu-parse-agent.blueriver-1234abcd.eastus2.azurecontainerapps.io`).

### Verify Deployment

```bash
# Get the app URL
APP_URL=$(az containerapp show \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.configuration.ingress.fqdn" -o tsv)

echo "App URL: https://${APP_URL}"

# Test health endpoint
curl "https://${APP_URL}/health"
# Expected: {"status":"healthy"}
```

---

## Step 5: Configure Secrets

Secrets are stored securely in ACA and injected as environment variables. **Never pass sensitive values as plain environment variables.**

### Set Secrets

```bash
az containerapp secret set \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --secrets \
    nim-endpoint="https://integrate.api.nvidia.com/v1" \
    nim-api-key="nvapi-your-key-here" \
    parser-api-key="your-strong-api-key-here"
```

### Bind Secrets to Environment Variables

```bash
az containerapp update \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --set-env-vars \
    "NIM_ENDPOINT=secretref:nim-endpoint" \
    "NIM_API_KEY=secretref:nim-api-key" \
    "PARSER_API_KEY=secretref:parser-api-key"
```

### Verify Secrets

```bash
az containerapp secret list \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[].name" -o tsv
# Expected: nim-endpoint, nim-api-key, parser-api-key
```

---

## Step 6: Add GPU Workload Profile (Optional)

GPU workload profiles enable NVIDIA GPU access for the Nemotron Parse NIM. This step is optional — mock mode works without GPUs.

### Check GPU Availability in Your Region

```bash
az containerapp env workload-profile list-supported \
  --location "${LOCATION}" \
  --query "[?contains(name, 'NC')]" -o table
```

### Add GPU Profile

```bash
az containerapp env workload-profile add \
  --name "${ACA_ENV_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --workload-profile-name "gpu-profile" \
  --workload-profile-type "NC24-A100" \
  --min-nodes 0 \
  --max-nodes 1
```

Available GPU profile types:

| Profile Type | GPU | vCPUs | Memory | Use Case |
|-------------|-----|-------|--------|----------|
| `NC8-T4` | 1x T4 (16 GB) | 8 | 56 GiB | Dev/test, small models |
| `NC16-A10` | 1x A10 (24 GB) | 16 | 110 GiB | Production, Nemotron Parse |
| `NC24-A100` | 1x A100 (80 GB) | 24 | 220 GiB | Large models, high throughput |

### Assign the GPU Profile to the App

```bash
az containerapp update \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --workload-profile-name "gpu-profile"
```

### Verify GPU Assignment

```bash
az containerapp show \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.workloadProfileName" -o tsv
# Expected: gpu-profile
```

---

## Step 7: Configure Custom Domain and TLS (Optional)

### Add a Custom Domain

```bash
az containerapp hostname add \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --hostname "parse-agent.yourdomain.com"
```

### Bind a Managed Certificate

```bash
az containerapp hostname bind \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --hostname "parse-agent.yourdomain.com" \
  --environment "${ACA_ENV_NAME}" \
  --validation-method CNAME
```

---

## Step 8: Connect the Orchestrator

Update your local `.env` to point the orchestrator at the deployed parser service:

```env
# Replace with your actual ACA app URL
PARSER_URL=https://gpu-parse-agent.blueriver-1234abcd.eastus2.azurecontainerapps.io
PARSER_API_KEY=your-strong-api-key-here
```

### Test the Connection

```bash
# Run demo against the deployed parser
python run_demo.py --mode direct
```

---

## Automated Deployment Script

A one-command deployment script is provided at `deploy/aca_deploy.sh`:

```bash
# Make executable
chmod +x deploy/aca_deploy.sh

# Run with defaults
./deploy/aca_deploy.sh

# Or override configuration
RESOURCE_GROUP=my-rg \
LOCATION=westus3 \
ACR_NAME=myacrname \
./deploy/aca_deploy.sh
```

### Configurable Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOURCE_GROUP` | `rg-multi-agent-demo` | Azure resource group name |
| `LOCATION` | `eastus2` | Azure region |
| `ACR_NAME` | `acrmultiagentdemo` | Container registry name (globally unique) |
| `ACA_ENV_NAME` | `multi-agent-env` | Container Apps environment name |
| `ACA_APP_NAME` | `gpu-parse-agent` | Container app name |
| `IMAGE_TAG` | `latest` | Docker image tag |
| `ACA_GPU_SKU` | `A10` | GPU SKU type |

---

## Monitoring and Observability

### View Logs

```bash
# Stream live logs
az containerapp logs show \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --type console \
  --follow

# Query recent logs
az containerapp logs show \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --type console \
  --tail 100
```

### View Metrics

```bash
# Check replicas
az containerapp replica list \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  -o table
```

### Connect OpenTelemetry to Azure Monitor

1. Create an Application Insights resource:

```bash
az monitor app-insights component create \
  --app multi-agent-insights \
  --location "${LOCATION}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "connectionString" -o tsv
```

2. Update the app with the OTLP endpoint:

```bash
APPINSIGHTS_CONN=$(az monitor app-insights component show \
  --app multi-agent-insights \
  --resource-group "${RESOURCE_GROUP}" \
  --query "connectionString" -o tsv)

az containerapp update \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --set-env-vars \
    "APPLICATIONINSIGHTS_CONNECTION_STRING=${APPINSIGHTS_CONN}"
```

### Use Jaeger for Local Trace Visualization

```bash
# Run Jaeger locally
docker run -d --name jaeger \
  -p 16686:16686 \
  -p 4317:4317 \
  jaegertracing/all-in-one:latest

# Point the app at Jaeger
# Set OTEL_EXPORTER_OTLP_ENDPOINT=http://host.docker.internal:4317
```

Open [http://localhost:16686](http://localhost:16686) to view traces.

---

## Scaling Configuration

### HTTP Scaling Rule (Default)

Scale based on concurrent HTTP requests:

```bash
az containerapp update \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --min-replicas 0 \
  --max-replicas 5 \
  --scale-rule-name http-rule \
  --scale-rule-type http \
  --scale-rule-http-concurrency 10
```

### Custom Scaling Rule

Scale based on request rate:

```bash
az containerapp update \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --scale-rule-name queue-rule \
  --scale-rule-type azure-queue \
  --scale-rule-metadata "queueName=parse-requests" "queueLength=5"
```

### Scale-to-Zero Behavior

With `--min-replicas 0`, the app scales to zero after a period of inactivity. The first request after scale-down triggers a **cold start** (~5-15 seconds for CPU, ~30-60 seconds for GPU).

For demos, consider setting `--min-replicas 1` to avoid cold start delays:

```bash
az containerapp update \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --min-replicas 1
```

---

## Cost Management

### Estimated Costs (Pay-as-you-go)

| Resource | SKU | Cost (approx.) |
|----------|-----|-----------------|
| ACA (CPU) | 4 vCPU, 8 GiB | ~$0.10/hr when active, $0 at scale-to-zero |
| ACA (A10 GPU) | NC16-A10 | ~$1.50/hr when active |
| ACA (A100 GPU) | NC24-A100 | ~$4.00/hr when active |
| ACR | Standard | ~$5/month |
| Resource Group | - | Free |

### Cost Optimization Tips

1. **Scale to zero** — Set `--min-replicas 0` for non-production
2. **Use mock mode** — Avoid GPU costs during development
3. **Tag resources** for cost tracking:
   ```bash
   az group update \
     --name "${RESOURCE_GROUP}" \
     --tags project=multi-agent-demo environment=dev
   ```
4. **Set budget alerts**:
   ```bash
   az consumption budget create \
     --budget-name multi-agent-budget \
     --resource-group "${RESOURCE_GROUP}" \
     --amount 100 \
     --time-grain Monthly \
     --category Cost
   ```
5. **Delete when done**:
   ```bash
   az group delete --name "${RESOURCE_GROUP}" --yes --no-wait
   ```

---

## CI/CD with GitHub Actions

Create `.github/workflows/deploy-aca.yml`:

```yaml
name: Deploy to ACA

on:
  push:
    branches: [main]
    paths:
      - 'parser_service/**'
      - 'Dockerfile'
      - 'requirements.txt'

env:
  RESOURCE_GROUP: rg-multi-agent-demo
  ACR_NAME: acrmultiagentdemo
  ACA_APP_NAME: gpu-parse-agent

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Build and push to ACR
        run: |
          az acr build \
            --registry ${{ env.ACR_NAME }} \
            --image ${{ env.ACA_APP_NAME }}:${{ github.sha }} \
            --image ${{ env.ACA_APP_NAME }}:latest \
            --file Dockerfile \
            .

      - name: Deploy to ACA
        run: |
          az containerapp update \
            --name ${{ env.ACA_APP_NAME }} \
            --resource-group ${{ env.RESOURCE_GROUP }} \
            --image ${{ env.ACR_NAME }}.azurecr.io/${{ env.ACA_APP_NAME }}:${{ github.sha }}
```

### Set Up Azure Credentials for GitHub Actions

```bash
# Create a service principal with Contributor access
az ad sp create-for-rbac \
  --name "github-multi-agent-deploy" \
  --role Contributor \
  --scopes /subscriptions/<SUB_ID>/resourceGroups/rg-multi-agent-demo \
  --sdk-auth

# Copy the JSON output to GitHub > Settings > Secrets > AZURE_CREDENTIALS
```

---

## Troubleshooting

### "ContainerAppOperationError: Provisioning failed"

- Check that the region supports Container Apps: `az provider show --namespace Microsoft.App --query "resourceTypes[?resourceType=='containerApps'].locations" -o tsv`
- Verify ACR image exists: `az acr repository show-tags --name ${ACR_NAME} --repository ${ACA_APP_NAME}`

### "Replica not ready — CrashLoopBackOff"

- Check logs: `az containerapp logs show --name ${ACA_APP_NAME} --resource-group ${RESOURCE_GROUP} --type console`
- Common cause: missing environment variables or incorrect `PARSER_API_KEY`
- Verify locally first with `docker run`

### "GPU workload profile not available"

- GPU profiles are region-dependent. Check availability:
  ```bash
  az containerapp env workload-profile list-supported --location eastus2 -o table
  ```
- Try regions: `eastus2`, `westus3`, `swedencentral`, `northeurope`

### "Connection refused" from Orchestrator

- Verify the app is running: `curl https://<APP_URL>/health`
- Check ingress is set to `external`
- Ensure `PARSER_API_KEY` matches between orchestrator `.env` and ACA secrets

### "Scale-to-zero cold start too slow"

- Set `--min-replicas 1` to keep one instance warm
- For GPU workloads, cold start can be 30-60s — this is expected

### "ACR authentication failed"

- Refresh credentials: `az acr login --name ${ACR_NAME}`
- Or use managed identity: `az containerapp registry set --name ${ACA_APP_NAME} --resource-group ${RESOURCE_GROUP} --server ${ACR_NAME}.azurecr.io --identity system`

---

## Cleanup

Remove all deployed resources:

```bash
# Delete the entire resource group (irreversible)
az group delete \
  --name "${RESOURCE_GROUP}" \
  --yes \
  --no-wait

echo "Cleanup initiated. Resources will be deleted in the background."
```

---

## Next Steps

- [Deploy Models with Azure AI Foundry](deploying_models_foundry.md) — Set up the orchestrator agent
- [Demo Script](demo_script.md) — 2-minute talk track for conferences
- [Troubleshooting](troubleshooting.md) — Common issues and fixes
