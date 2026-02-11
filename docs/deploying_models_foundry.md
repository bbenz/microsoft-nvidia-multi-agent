# Deploying Models with Microsoft Azure AI Foundry

This guide walks through setting up the orchestrator agent using **Azure AI Foundry** (formerly Azure AI Studio) and configuring the OpenAI models required for the Coordinator Agent in this demo.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Step 1: Create an Azure AI Foundry Hub](#step-1-create-an-azure-ai-foundry-hub)
4. [Step 2: Create an Azure AI Foundry Project](#step-2-create-an-azure-ai-foundry-project)
5. [Step 3: Deploy a GPT-4o Model](#step-3-deploy-a-gpt-4o-model)
6. [Step 4: Configure the Orchestrator](#step-4-configure-the-orchestrator)
7. [Step 5: Deploy NVIDIA Nemotron Parse NIM](#step-5-deploy-nvidia-nemotron-parse-nim)
8. [Step 6: Verify End-to-End](#step-6-verify-end-to-end)
9. [Model Selection Guide](#model-selection-guide)
10. [Cost Optimization](#cost-optimization)
11. [Troubleshooting](#troubleshooting)

---

## Overview

This demo uses two model deployments:

| Component | Model | Deployment Target |
|-----------|-------|-------------------|
| **Coordinator Agent** | GPT-4o (or GPT-4o-mini) | Azure AI Foundry (Azure OpenAI) |
| **GPU Parse Specialist** | NVIDIA Nemotron Parse | Azure Container Apps (NIM container) |

The Coordinator Agent uses the **OpenAI Responses API** with tool-use to orchestrate the workflow. Azure AI Foundry provides a managed deployment of GPT-4o that is fully compatible with the OpenAI SDK.

---

## Prerequisites

- **Azure subscription** with access to Azure OpenAI Service
- **Azure CLI** installed and authenticated (`az login`)
- **Azure AI Foundry access** — request access at [https://ai.azure.com](https://ai.azure.com) if needed
- **Python 3.10+** with dependencies installed (`pip install -r requirements.txt`)

---

## Step 1: Create an Azure AI Foundry Hub

A Hub is the top-level resource that manages your AI projects, compute, and connections.

### Via Azure Portal

1. Go to [https://ai.azure.com](https://ai.azure.com)
2. Click **+ Create hub**
3. Configure:
   - **Hub name:** `multi-agent-hub`
   - **Subscription:** Select your subscription
   - **Resource group:** `rg-multi-agent-demo` (or create new)
   - **Region:** `East US 2` (recommended — supports GPT-4o and GPU workloads)
4. Click **Create**

### Via Azure CLI

```bash
# Create resource group (if not already created)
az group create \
  --name rg-multi-agent-demo \
  --location eastus2

# Create the AI Foundry hub
az ml workspace create \
  --name multi-agent-hub \
  --resource-group rg-multi-agent-demo \
  --kind hub \
  --location eastus2
```

> **Note:** The hub automatically provisions an Azure OpenAI resource, Storage account, and Key Vault.

---

## Step 2: Create an Azure AI Foundry Project

Projects organize your deployments, data, and experiments within a hub.

### Via Azure AI Foundry Portal

1. In [https://ai.azure.com](https://ai.azure.com), open your hub
2. Click **+ New project**
3. Name it `multi-agent-project`
4. Click **Create**

### Via Azure CLI

```bash
az ml workspace create \
  --name multi-agent-project \
  --resource-group rg-multi-agent-demo \
  --kind project \
  --hub-id /subscriptions/<SUB_ID>/resourceGroups/rg-multi-agent-demo/providers/Microsoft.MachineLearningServices/workspaces/multi-agent-hub
```

---

## Step 3: Deploy a GPT-4o Model

The Coordinator Agent requires a model that supports tool-use (function calling) via the Responses API.

### Via Azure AI Foundry Portal

1. In your project, go to **Deployments** > **+ Create deployment**
2. Select **Model catalog** > **Azure OpenAI** > **gpt-4o**
3. Configure:
   - **Deployment name:** `gpt-4o`
   - **Model version:** Latest (e.g., `2024-11-20`)
   - **Deployment type:** `Standard` (recommended) or `Global Standard`
   - **Tokens per minute rate limit:** `80K` (adjust based on expected load)
4. Click **Deploy**
5. Once deployed, note the:
   - **Endpoint URL** (e.g., `https://<resource>.openai.azure.com/`)
   - **API Key** (under **Keys and Endpoint**)

### Via Azure CLI

```bash
# Create Azure OpenAI resource (if not using the hub's auto-provisioned one)
az cognitiveservices account create \
  --name multi-agent-openai \
  --resource-group rg-multi-agent-demo \
  --kind OpenAI \
  --sku S0 \
  --location eastus2

# Deploy GPT-4o
az cognitiveservices account deployment create \
  --name multi-agent-openai \
  --resource-group rg-multi-agent-demo \
  --deployment-name gpt-4o \
  --model-name gpt-4o \
  --model-version "2024-11-20" \
  --model-format OpenAI \
  --sku-capacity 80 \
  --sku-name Standard

# Get the endpoint and key
az cognitiveservices account show \
  --name multi-agent-openai \
  --resource-group rg-multi-agent-demo \
  --query "properties.endpoint" -o tsv

az cognitiveservices account keys list \
  --name multi-agent-openai \
  --resource-group rg-multi-agent-demo \
  --query "key1" -o tsv
```

---

## Step 4: Configure the Orchestrator

Update your `.env` file with the Azure OpenAI credentials:

### Option A: Azure OpenAI with OpenAI-compatible SDK

```env
# Use the Azure OpenAI endpoint directly with the OpenAI SDK
OPENAI_API_KEY=<your-azure-openai-api-key>
OPENAI_MODEL=gpt-4o

# For Azure OpenAI, also set these:
OPENAI_API_BASE=https://<your-resource>.openai.azure.com/
OPENAI_API_VERSION=2024-12-01-preview
OPENAI_API_TYPE=azure
```

### Option B: Standard OpenAI API

If using OpenAI directly (not Azure):

```env
OPENAI_API_KEY=sk-your-openai-key
OPENAI_MODEL=gpt-4o
```

### Verify the Connection

```bash
# Quick test — should return model info
python -c "
from openai import AzureOpenAI
import os
client = AzureOpenAI(
    api_key=os.getenv('OPENAI_API_KEY'),
    api_version='2024-12-01-preview',
    azure_endpoint=os.getenv('OPENAI_API_BASE', '')
)
resp = client.chat.completions.create(
    model='gpt-4o',
    messages=[{'role': 'user', 'content': 'Say hello'}],
    max_tokens=10
)
print(resp.choices[0].message.content)
"
```

---

## Step 5: Deploy NVIDIA Nemotron Parse NIM

The GPU Parse Specialist uses NVIDIA Nemotron Parse for structured document extraction. You have three deployment options:

### Option A: NVIDIA API Catalog (Fastest for Dev/Test)

1. Go to [https://build.nvidia.com](https://build.nvidia.com)
2. Search for **Nemotron Parse**
3. Click **Get API Key** and copy the key
4. Update `.env`:

```env
NIM_ENDPOINT=https://integrate.api.nvidia.com/v1
NIM_MODEL_ID=nvidia/nemotron-parse
NIM_API_KEY=nvapi-your-key-here
```

### Option B: Self-Hosted NIM on Azure Container Apps

Deploy the NIM container alongside the parser service. See [Deploying to ACA](deploying_to_aca.md) for full instructions.

```bash
# Pull the NIM container
docker pull nvcr.io/nim/nvidia/nemotron-parse:latest

# Run locally for testing
docker run --gpus all -p 8000:8000 \
  -e NIM_MODEL_NAME=nvidia/nemotron-parse \
  nvcr.io/nim/nvidia/nemotron-parse:latest
```

Update `.env`:
```env
NIM_ENDPOINT=http://localhost:8000/v1
NIM_MODEL_ID=nvidia/nemotron-parse
NIM_API_KEY=not-required-for-local
```

### Option C: Mock Mode (No GPU Required)

For demos without GPU access, leave `NIM_ENDPOINT` blank. The parser service will use built-in mock data that produces deterministic, spec-compliant output.

```env
NIM_ENDPOINT=
```

---

## Step 6: Verify End-to-End

### Direct Mode (No LLM Required)

```bash
# Generate sample PDFs
python sample_data/generate_sample_invoice_pdf.py

# Serve PDFs
cd sample_data && python -m http.server 8000 &
cd ..

# Run demo
python run_demo.py --mode direct
```

### Agent Mode (Requires GPT-4o)

```bash
# Ensure .env has OPENAI_API_KEY set
python run_demo.py --mode agent
```

Expected output should show the PDF being parsed, line items extracted, and anomalies detected.

---

## Model Selection Guide

| Model | Tool-Use Support | Cost | Latency | Recommended For |
|-------|-----------------|------|---------|-----------------|
| **gpt-4o** | Yes | $$ | ~1-2s | Production demos, best accuracy |
| **gpt-4o-mini** | Yes | $ | ~0.5-1s | Development, testing, cost-sensitive |
| **gpt-4-turbo** | Yes | $$$ | ~2-3s | Legacy compatibility |
| **gpt-3.5-turbo** | Yes | $ | ~0.5s | Not recommended (lower tool-use accuracy) |

For this demo, **gpt-4o** is recommended for the best tool-use behavior and summary quality.

---

## Cost Optimization

### Azure OpenAI

- Use **Provisioned Throughput** (PTU) for predictable demo workloads
- Use **Global Standard** deployment for lowest per-token cost
- Set appropriate rate limits to avoid unexpected charges
- Consider **gpt-4o-mini** for development iterations

### NVIDIA NIM

- Use **NVIDIA API Catalog** free tier for initial testing (1,000 free credits)
- Self-host on ACA with **scale-to-zero** for production demos
- Use A10 GPUs (more cost-effective) instead of A100s for this workload

### Mock Mode

- For conference demos where network reliability is a concern, use mock mode
- Zero cost, deterministic output, works offline

---

## Troubleshooting

### "AuthenticationError: Incorrect API key"

- Verify the API key is set correctly in `.env`
- For Azure OpenAI, ensure `OPENAI_API_BASE` and `OPENAI_API_VERSION` are also set
- Check that the key hasn't been rotated

### "Model not found"

- Verify the deployment name matches `OPENAI_MODEL` in `.env`
- Azure OpenAI uses deployment names, not model names — these can differ
- Check that the deployment is in **Succeeded** state in the portal

### "Rate limit exceeded"

- Increase the TPM (tokens per minute) quota in the Azure portal
- For demos, 80K TPM is usually sufficient
- Add retry logic or switch to a Global Standard deployment

### "Region not available"

- GPT-4o is available in most regions, but check [Azure OpenAI model availability](https://learn.microsoft.com/azure/ai-services/openai/concepts/models#model-summary-table-and-region-availability)
- Recommended region: **East US 2** (supports both GPT-4o and GPU workloads)

### NIM Connection Issues

- Verify `NIM_ENDPOINT` is reachable: `curl $NIM_ENDPOINT/v1/models`
- For self-hosted NIM, ensure the container is running and healthy
- For NVIDIA API Catalog, check your API key at [https://build.nvidia.com](https://build.nvidia.com)

---

## Next Steps

- [Deploy to Azure Container Apps](deploying_to_aca.md) — Deploy the parser service with GPU support
- [Demo Script](demo_script.md) — 2-minute talk track for conferences
- [Troubleshooting](troubleshooting.md) — Common issues and fixes
