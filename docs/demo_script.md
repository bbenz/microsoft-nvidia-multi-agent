# Demo Script — 2-Minute Conference Talk Track

## Title Slide (10 seconds)

> "Today I'll show you a hybrid multi-agent workflow combining Microsoft and NVIDIA — an orchestrator agent delegating to a GPU-powered specialist for invoice analysis."

## Architecture Overview (20 seconds)

> "Here's the architecture. We have two agents:
>
> **Agent 1** is the Coordinator — built with the OpenAI Responses API, running in Microsoft Foundry Agent Service. It receives natural language requests and orchestrates the workflow.
>
> **Agent 2** is the GPU Parse Specialist — a FastAPI service deployed on Azure Container Apps with serverless NVIDIA GPUs. It uses Nemotron Parse NIM for structured document extraction."

## Live Demo — Run It (30 seconds)

> "Let me run this live. One command."

```
python run_demo.py
```

> "The orchestrator receives the PDF URL, calls the parse specialist agent, which extracts line items, normalizes the data, and runs anomaly detection — all in under a second."

_Wait for output to appear._

## Walk Through the Output (30 seconds)

> "Look at the results:
>
> - We extracted 5 line items, vendor, totals — all structured JSON with bounding boxes.
> - Two anomalies were automatically detected:
>   1. The subtotal on the invoice says $412 but the line items only add up to $392 — a $20 discrepancy.
>   2. 'Premium Support' at $250 is flagged as a price outlier — it's over 5× the median unit price of $42.
>
> This is the kind of validation that catches real errors in financial documents."

## Observability (15 seconds)

> "Every step is traced end-to-end with OpenTelemetry — W3C trace context propagated from orchestrator to specialist. You can see the full agent chain in Jaeger or Azure Monitor using the trace ID."

## Deployment Story (15 seconds)

> "The specialist agent deploys to Azure Container Apps with a single script. It scales to zero when idle and auto-scales with GPU workload profiles — A10s or A100s. The orchestrator runs in Foundry Agent Service."

## Close (10 seconds)

> "This is a production pattern — multi-agent coordination, GPU-accelerated document intelligence, full observability. The entire repo is open source. Try it yourself."

---

## Key Talking Points (if Q&A)

- **Why two agents?** Separation of concerns — the LLM orchestrates, the specialist does deterministic extraction with purpose-built models.
- **Why NVIDIA NIM?** Nemotron Parse is optimized for structured document extraction on GPUs — faster and more accurate than generic OCR.
- **Why Azure Container Apps?** Serverless GPU allocation — pay only when processing, scale to zero.
- **Mock mode?** The demo works without any API keys. Set `NIM_ENDPOINT` to use real Nemotron Parse.
