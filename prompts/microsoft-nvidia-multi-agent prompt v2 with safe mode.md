You are a senior engineer building a keynote-safe, demo-grade reference implementation for a Microsoft + NVIDIA hybrid multi-agent workflow.

Your output MUST be runnable, deterministic, and resilient to:
- No internet / unstable Wi-Fi
- Model endpoint timeouts or rate limits
- Nemotron Parse NIM unavailable
- OTLP collector unavailable
- Public PDF URL unavailable
- Cold starts on ACA

DO NOT ask clarifying questions. Proceed with the requirements below.

========================================================
GOAL
========================================================

Build a single-repo Python project demonstrating:
1) Coordinator / Orchestrator Agent
   - Python
   - Uses OpenAI Python SDK (Responses API)
   - Runnable locally and deployable to Foundry Agent Service
   - Delegates structured extraction to a specialist agent

2) GPU Parse Specialist Agent
   - Python FastAPI service
   - Deployable to Azure Container Apps (ACA) with serverless NVIDIA GPUs
   - Integrates Nemotron Parse NIM (remote endpoint or local container)
   - Provides robust normalization + anomaly detection

3) Governance + Observability
   - End-to-end OpenTelemetry tracing
   - Correlation IDs
   - Audit logs of tool calls (redacted)

========================================================
DEMO SCENARIO (LOCKED)
========================================================

User prompt:
“Here’s a PDF URL. Extract the line items into JSON and tell me if anything looks off.”

Flow:
- Orchestrator receives PDF URL
- Calls POST /parse on parser service
- Parser extracts invoice content and returns normalized JSON + warnings
- Orchestrator prints deterministic keynote output, including trace_id and request_id

========================================================
KEYNOTE SAFETY PRINCIPLES (MANDATORY)
========================================================

A) Demo must succeed even with ZERO external services available.
Implement layered fallback modes:

Mode 1: FULL_LIVE
- Uses real OpenAI Responses API + real parser service + real NIM
Mode 2: PARSER_LIVE_ORCH_MOCK
- Parser service live, orchestrator uses local deterministic “router” logic (no OpenAI call)
Mode 3: ORCH_LIVE_PARSER_MOCK
- Orchestrator uses OpenAI Responses API, parser returns deterministic mock extraction
Mode 4: FULL_OFFLINE (KEYNOTE SAFE)
- No network required
- Uses local sample PDF files
- Uses deterministic mock “parse” output
- Produces the EXACT same console output format every time

Select mode automatically by health checks, with explicit overrides:
- DEMO_MODE=auto|full_live|parser_live_orch_mock|orch_live_parser_mock|full_offline

Health checks must be fast (<2 seconds each) with timeouts.
If anything fails, fall back gracefully without crashing.

B) Deterministic output is required.
- Always produce the same “anomaly” demo output by default.
- Use seeded randomness where unavoidable, but prefer no randomness.

C) Never block on OpenTelemetry.
- If OTLP exporter fails, fall back to console exporter and continue.
- Always print a “Trace exported …” line even if it’s console-only; clarify locally.

D) Never block on public PDF URLs.
- Always include local PDF files and a local file URL option.
- If URL fetch fails, fall back to local file.

E) Never block on ACA cold start.
- Provide a “warmup” endpoint and a warmup step in run_demo.py
- But if warmup fails, fall back to local mock mode.

========================================================
STACK (LOCKED)
========================================================

- Python everywhere
- Single repo
- Orchestrator uses OpenAI Python SDK Responses API when in live modes
- Parser: FastAPI
- Auth: X-API-Key required when calling /parse (even locally)
- Input: PDF URL; multi-page support (but offline mode may use local files)
- Bounding boxes normalized [0..1] with {x,y,w,h,page}

========================================================
REPO LAYOUT (REQUIRED)
========================================================

/
  README.md
  .env.example
  pyproject.toml (or requirements.txt)
  run_demo.py
  out/ (generated)
  orchestrator/
    app.py
    coordinator.py
    responses_client.py
    decision.py              # deterministic router/fallback logic
    audit.py
    otel.py
    config.py
    health.py
  parser_service/
    app.py
    routes.py
    models.py
    nim_client.py
    pdf_fetch.py
    normalize.py
    anomalies.py
    audit.py
    otel.py
    config.py
    health.py
    Dockerfile
  sample_data/
    generate_sample_invoice_pdf.py
    sample_invoice_clean.pdf
    sample_invoice_anomaly.pdf
    canned/
      parsed_invoice_clean.json
      parsed_invoice_anomaly.json
  infra/
    aca_deploy.md
    scripts/
      build_and_push.sh
      aca_create_or_update.sh
  docs/
    demo_script.md
    troubleshooting.md
    api_contract.md
    keynote_runbook.md         # “if Wi-Fi dies” steps

========================================================
CONFIGURATION (ENV VARS)
========================================================

OPENAI_API_KEY=
OPENAI_MODEL=                 # variable placeholder
PARSER_URL=
PARSER_API_KEY=
NIM_MODE=remote|local|mock
NIM_ENDPOINT=
NIM_MODEL_ID=
NIM_API_KEY=
ACA_GPU_SKU=                  # placeholder
OTEL_EXPORTER_OTLP_ENDPOINT=
LOG_LEVEL=
DEMO_MODE=auto
DEMO_PDF_URL=                 # pre-canned public URL, but never required
DEMO_PDF_LOCAL=sample_data/sample_invoice_anomaly.pdf

========================================================
API CONTRACT (LOCKED)
========================================================

POST /parse
Headers:
  X-API-Key: required
  X-Request-Id: optional (always provided by orchestrator)
Body:
  { "pdf_url": "https://..." }

Response:
  request_id, trace_id, invoice{...}, warnings[], summary

Also add:
GET /healthz
GET /warmup

========================================================
ANOMALY RULES (LOCKED)
========================================================

Implement exactly:
1) subtotal != sum(line_items.amount) (epsilon=0.01)
2) unit_price > 5x median unit_price (ignore zeros)
3) missing vendor/date/total

Return warnings[] and summary string.

========================================================
AUDIT LOGGING (MANDATORY)
========================================================

- Orchestrator logs tool_call and tool_result with request_id + trace_id.
- Parser logs request_received and parse_completed.
- Redact PDF URL query string and never store PDF bytes.

========================================================
OPEN TELEMETRY (MANDATORY, NON-BLOCKING)
========================================================

- Trace propagation via W3C traceparent headers
- Spans:
  Orchestrator: orchestrator.handle_request, orchestrator.call_parser
  Parser: parser.handle_parse, parser.fetch_pdf, parser.call_nim, parser.normalize, parser.anomaly_checks

If OTLP fails, fallback to console exporter and continue.

========================================================
DEMO-READY OUTPUT MODE (MANDATORY)
========================================================

Provide pre-canned demo defaults that always work:

Default behavior of run_demo.py:
- DEMO_MODE=auto
- Use DEMO_PDF_URL if reachable; else use DEMO_PDF_LOCAL
- Prefer parser service if reachable; else use mock parser
- Prefer OpenAI Responses API if reachable; else use deterministic decision logic

Create “canned” parsed outputs:
- sample_data/canned/parsed_invoice_clean.json
- sample_data/canned/parsed_invoice_anomaly.json
These must match the required output schema and include bbox.

In FULL_OFFLINE mode:
- Do not call OpenAI
- Do not call parser service
- Read canned JSON and print results

========================================================
EXACT CONSOLE OUTPUT FORMAT (LOCKED)
========================================================

When run_demo.py executes in its default anomaly demo, print EXACTLY:

--------------------------------------------------
🧾 MULTI-AGENT INVOICE ANALYSIS DEMO
--------------------------------------------------

PDF: <url-or-local>
Request ID: <uuid>
Trace ID: <trace>

Calling Parse Specialist Agent...
✓ Parse complete

--------------------------------------------------
📊 EXTRACTED TOTALS
--------------------------------------------------
Vendor: Alpine Office Supplies
Invoice: INV-1042
Subtotal: $412.00
Tax: $32.96
Total: $444.96

--------------------------------------------------
⚠️ ANOMALIES DETECTED
--------------------------------------------------
1. Subtotal mismatch: lines sum to $392.00 but subtotal is $412.00
2. High unit price outlier: "Premium Support" = $250 vs median $42

--------------------------------------------------
🧠 AGENT SUMMARY
--------------------------------------------------
The invoice was parsed successfully. Two anomalies were detected:
- The subtotal does not match the sum of line items.
- One line item has a significantly higher unit price than others.

This may indicate a calculation error or incorrect entry.

--------------------------------------------------
🔭 OBSERVABILITY
--------------------------------------------------
Trace exported via OpenTelemetry
Use trace_id above in your dashboard to view full agent chain.

Demo complete.
--------------------------------------------------

This format MUST be exact and deterministic.

========================================================
REQUIRED “KEYNOTE RUNBOOK”
========================================================

docs/keynote_runbook.md must include:
- Best-case (full live) steps
- No Wi-Fi steps (full_offline)
- OTLP down steps
- Parser down steps
- NIM down steps
- One-liner environment overrides to force each mode
- A “last resort” command that always succeeds:
  DEMO_MODE=full_offline python run_demo.py

========================================================
DEPLOYMENT ARTIFACTS (ACA)
========================================================

Provide:
- parser_service/Dockerfile
- infra/aca_deploy.md
- infra/scripts/*.sh
Include GPU configuration placeholders and comments.

========================================================
DELIVERY FORMAT (MANDATORY)
========================================================

Output in this order:
1) Assumptions
2) Implementation plan
3) Full file tree
4) Contents of every file (code + docs + scripts)
5) Example commands to run each mode
6) Sample output (must match the exact console output format)

Do not summarize. Generate full implementation.
