# Microsoft + NVIDIA Hybrid Multi-Agent Workflow

A production-grade reference implementation demonstrating a **hybrid multi-agent workflow** combining Microsoft Foundry Agent Service with NVIDIA NIM microservices on Azure Container Apps with serverless GPUs.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        User / Demo Runner                       │
│                       (run_demo.py)                             │
└──────────────┬──────────────────────────────────────────────────┘
               │  "Extract line items and flag anomalies"
               ▼
┌──────────────────────────────┐    W3C traceparent    ┌──────────────────────────────┐
│    Coordinator / Orchestrator │ ──── POST /parse ───▶ │   GPU Parse Specialist Agent  │
│                              │                       │                              │
│  • OpenAI Responses API      │                       │  • FastAPI on ACA + GPU      │
│  • Tool: parse_invoice       │                       │  • Nemotron Parse NIM        │
│  • Microsoft Foundry Agent   │ ◀── JSON response ── │  • Normalize + Anomaly       │
│  • Audit logging             │                       │  • Audit logging             │
└──────────────────────────────┘                       └──────────────────────────────┘
               │                                                    │
               └────────────────┬───────────────────────────────────┘
                                ▼
                    ┌───────────────────────┐
                    │   OpenTelemetry OTLP  │
                    │   (Jaeger / Aspire /  │
                    │    Azure Monitor)     │
                    └───────────────────────┘
```

## Demo Scenario

**User prompt:** _"Here's a PDF URL. Extract the line items into JSON and tell me if anything looks off."_

The orchestrator delegates structured extraction to the GPU parse specialist, which:
1. Fetches the PDF
2. Extracts invoice data via NVIDIA Nemotron Parse NIM (or mock mode)
3. Normalizes the data
4. Runs anomaly detection (subtotal mismatch, price outliers, missing fields)
5. Returns structured JSON with warnings

## Quick Start

### Prerequisites

- Python 3.10+
- pip

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Generate Sample Invoices

```bash
python sample_data/generate_sample_invoice_pdf.py
```

### 3. Serve Sample PDFs (in a separate terminal)

```bash
cd sample_data && python -m http.server 8000
```

### 4. Run the Demo

```bash
python run_demo.py
```

This runs in **direct mode** — deterministic, no OpenAI API key required.

### 5. Run with OpenAI Agent (optional)

```bash
cp .env.example .env
# Edit .env and set OPENAI_API_KEY
python run_demo.py --mode agent
```

## Configuration

All settings via environment variables (see `.env.example`):

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENAI_API_KEY` | OpenAI API key (agent mode only) | — |
| `OPENAI_MODEL` | Model to use | `gpt-4o` |
| `PARSER_URL` | Parser service URL | `http://localhost:8001` |
| `PARSER_API_KEY` | API key for parser auth | `demo-api-key-change-me` |
| `NIM_ENDPOINT` | NVIDIA NIM endpoint (blank = mock) | — |
| `NIM_MODEL_ID` | NIM model identifier | `nvidia/nemotron-parse` |
| `NIM_API_KEY` | NIM API key | — |
| `ACA_GPU_SKU` | GPU SKU for ACA deployment | `A10` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP collector endpoint | — |
| `LOG_LEVEL` | Logging level | `INFO` |
| `DEMO_PDF_URL` | PDF URL for demo | `http://localhost:8000/sample_invoice_anomaly.pdf` |

## Project Structure

```
├── run_demo.py                    # One-command demo entry point
├── requirements.txt               # Python dependencies
├── .env.example                   # Environment template
├── Dockerfile                     # Parser service container
├── orchestrator/
│   ├── agent.py                   # Coordinator agent (OpenAI Responses API)
│   ├── config.py                  # Environment configuration
│   ├── telemetry.py               # OpenTelemetry setup
│   └── audit.py                   # Structured audit logging
├── parser_service/
│   ├── main.py                    # FastAPI application
│   ├── config.py                  # Environment configuration
│   ├── models.py                  # Pydantic data models
│   ├── nim_client.py              # Nemotron Parse NIM client + mock
│   ├── normalizer.py              # Data normalization
│   ├── anomaly.py                 # Anomaly detection rules
│   ├── telemetry.py               # OpenTelemetry setup
│   └── audit.py                   # Structured audit logging
├── sample_data/
│   └── generate_sample_invoice_pdf.py  # Deterministic PDF generator
├── deploy/
│   └── aca_deploy.sh              # Azure Container Apps deployment
└── docs/
    ├── demo_script.md             # 2-minute conference talk track
    └── troubleshooting.md         # Common failures
```

## ACA Deployment

### Build and Push

```bash
# Login to ACR
az acr login --name <your-acr>

# Build
docker build -t <your-acr>.azurecr.io/gpu-parse-agent:latest .

# Push
docker push <your-acr>.azurecr.io/gpu-parse-agent:latest
```

### Deploy with Script

```bash
chmod +x deploy/aca_deploy.sh
./deploy/aca_deploy.sh
```

### Manual GPU Configuration

```bash
# Add GPU workload profile
az containerapp env workload-profile add \
  --name multi-agent-env \
  --resource-group rg-multi-agent-demo \
  --workload-profile-name gpu-profile \
  --workload-profile-type NC24-A100 \
  --min-nodes 0 --max-nodes 1

# Assign app to GPU profile
az containerapp update \
  --name gpu-parse-agent \
  --resource-group rg-multi-agent-demo \
  --workload-profile-name gpu-profile
```

## Observability

- **Tracing:** W3C `traceparent` header propagated end-to-end
- **Correlation:** `X-Request-Id` header on all requests
- **OTLP Export:** Set `OTEL_EXPORTER_OTLP_ENDPOINT` to your collector
- **Spans:** `orchestrator.handle_request` → `orchestrator.call_parser` → `parser.handle_parse` → `parser.fetch_pdf` → `parser.call_nim` → `parser.normalize` → `parser.anomaly_checks`

## Anomaly Rules

| # | Rule | Code |
|---|------|------|
| 1 | `subtotal ≠ sum(line_items.amount)` | `SUBTOTAL_MISMATCH` |
| 2 | `unit_price > 5× median price` | `PRICE_OUTLIER` |
| 3 | Missing vendor, date, or total | `MISSING_FIELDS` |

## License

MIT
