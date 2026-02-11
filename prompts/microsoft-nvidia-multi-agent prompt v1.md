You are a senior engineer building a demo-quality reference implementation for a Microsoft + NVIDIA hybrid multi-agent workflow.

High-level goal
Build a single-repo project that demonstrates:
- A coordinator “Orchestrator Agent” (Python) that uses the OpenAI Python SDK Responses API to interpret a user request and delegate PDF invoice extraction to a specialist.
- A GPU “Parse Specialist Service” (Python, containerized) deployed to Azure Container Apps (ACA) with serverless NVIDIA GPUs, fronting an NVIDIA Nemotron Parse NIM (endpoint or local container).
- End-to-end observability with OpenTelemetry tracing across orchestrator → parser service → (optional) NIM call, including correlation IDs.
- Audit logging of tool calls (what was called, when, request-id, redacted payload metadata).

Demo scenario (the only scenario to implement)
User prompt:
“Here’s a PDF URL. Extract the line items into JSON and tell me if anything looks off.”
Flow:
1) Orchestrator receives: (a) a public PDF URL and (b) an optional user instruction text.
2) Orchestrator decides this is structured extraction → calls POST {PARSER_URL}/parse, passing the PDF URL.
3) Parser service downloads the PDF (multi-page supported), extracts line items via Nemotron Parse NIM, normalizes output, performs deterministic anomaly checks, and returns normalized JSON + warnings.
4) Orchestrator returns:
   - The normalized JSON (or a concise excerpt + saved artifact path)
   - A human summary with anomalies highlighted
   - Trace IDs for demo “observe” moment

Non-negotiable implementation constraints (lock these in)
- Language: Python for everything.
- Repo: single repo (monorepo).
- Orchestrator uses: OpenAI Python SDK, Responses API (not ChatCompletions).
- Parser service: FastAPI preferred (if you must pick), otherwise choose a simple Python web framework and document why.
- Inputs: PDF URL only; multi-page PDFs supported.
- Auth: API key required for /parse via header X-API-Key.
- Bounding boxes: normalized [0..1] with {x,y,w,h}, plus page index (1-based).
- Output: warnings[] with codes AND a freeform summary.
- Anomaly rules to implement:
  1) subtotal == sum(line_items.amount)
  2) suspiciously high unit_price vs median
  3) missing vendor/date/total
- Do NOT implement policy enforcement or secrets patterns beyond env vars.

Up front: ask clarifying questions ONLY if absolutely required to generate runnable code.
Otherwise, proceed with reasonable assumptions and state them.

Project layout (required)
/
  README.md
  .env.example
  pyproject.toml (or requirements.txt)
  orchestrator/
    app.py (or main.py)
    foundry_agent.py (if you wrap agent logic)
    otel.py
    audit.py
    config.py
  parser_service/
    app.py
    routes.py
    models.py (pydantic)
    nim_client.py
    pdf_fetch.py
    normalize.py
    anomalies.py
    otel.py
    audit.py
    config.py
    Dockerfile
  sample_data/
    generate_sample_invoice_pdf.py
    sample_invoice_1.pdf (generated)
    sample_invoice_2.pdf (generated)
  infra/
    aca_deploy.md
    scripts/
      build_and_push.sh
      aca_create_or_update.sh
  docs/
    demo_script.md
    troubleshooting.md
    api_contract.md

Configuration via environment variables (required)
Include an .env.example with these (and any needed extras):
- OPENAI_API_KEY=...
- OPENAI_MODEL=...                         # e.g., Nemotron Nano 9B v2 in Foundry Marketplace (string variable)
- PARSER_URL=https://...                   # ACA ingress URL
- PARSER_API_KEY=...                       # Shared API key for /parse
- NIM_MODE=remote|local
- NIM_ENDPOINT=http(s)://...               # if remote
- NIM_MODEL_ID=...                         # variable placeholder
- NIM_API_KEY=...                          # if needed
- ACA_GPU_SKU=...                          # placeholder variable
- ACA_ENV_NAME=...
- ACA_RESOURCE_GROUP=...
- ACA_LOCATION=...
- OTEL_EXPORTER_OTLP_ENDPOINT=http(s)://... # collector endpoint
- OTEL_SERVICE_NAME_ORCH=orchestrator
- OTEL_SERVICE_NAME_PARSER=parser-service
- LOG_LEVEL=INFO

Security requirements
- No secrets in code. Use env vars only.
- Parser service must reject requests missing/invalid X-API-Key (401).
- Audit logs must never store full PDF bytes. Log only:
  - pdf_url domain + path (optionally redact query string)
  - page count
  - timing, status, trace_id, request_id

Observability requirements (OpenTelemetry end-to-end)
- Implement OpenTelemetry tracing in both services.
- Propagate trace context from orchestrator to parser service:
  - Use W3C Trace Context (traceparent/tracestate headers).
- Use OTLP exporter (configurable) and a console fallback if OTLP endpoint is not set.
- Include request_id correlation:
  - Orchestrator generates request_id (UUID) per user request and passes as X-Request-Id.
  - Parser logs it and returns it.
- Add spans:
  Orchestrator:
    - span: orchestrator.handle_request
    - span: orchestrator.call_parser_service (attributes: parser_url, status_code, pdf_url_redacted)
  Parser:
    - span: parser.handle_parse
    - span: parser.fetch_pdf
    - span: parser.call_nim (if applicable)
    - span: parser.normalize_output
    - span: parser.anomaly_checks

API contract (required)
POST /parse
Headers:
  - X-API-Key: <required>
  - X-Request-Id: <optional, but orchestrator always provides>
Body JSON:
{
  "pdf_url": "https://public-host/path/file.pdf"
}
Response JSON (shape required):
{
  "request_id": "...",
  "trace_id": "...",
  "invoice": {
    "vendor": "...",
    "invoice_date": "YYYY-MM-DD",
    "invoice_number": "...",
    "currency": "USD",
    "subtotal": 0.0,
    "tax": 0.0,
    "total": 0.0,
    "line_items": [
      {
        "description": "...",
        "quantity": 1,
        "unit_price": 0.0,
        "amount": 0.0,
        "bbox": { "x":0.0, "y":0.0, "w":0.0, "h":0.0, "page":1 }
      }
    ]
  },
  "warnings": [
    { "code": "SUBTOTAL_MISMATCH", "message": "...", "details": { "expected": 0.0, "actual": 0.0 } }
  ],
  "summary": "Freeform, human-readable anomaly summary."
}

Normalization guidance
- The NIM output may be messy or model-specific. Implement a robust normalizer:
  - Coerce numeric strings to floats.
  - Default missing optional fields to null.
  - Convert bounding boxes to normalized [0..1] if model returns pixels:
    - If you have page width/height, normalize; if not, preserve but mark metadata.
- Multi-page PDFs:
  - Include page number for each bbox.
  - Support splitting per page for NIM if needed.

Anomaly detection details (implement exactly these)
1) SUBTOTAL_MISMATCH:
   - subtotal vs sum(line_items.amount), allow tolerance epsilon=0.01
2) HIGH_UNIT_PRICE_OUTLIER:
   - compute median(unit_price) across items with unit_price > 0
   - flag items where unit_price > (median * 5) or above a configured threshold
3) MISSING_REQUIRED_FIELDS:
   - vendor, invoice_date, total missing or empty

Tool-call audit logging (required)
- Orchestrator:
  - when deciding to call /parse, write an audit log entry:
    event="tool_call", tool="parser_service.parse", request_id, trace_id, pdf_url_redacted, timestamp
  - after response, audit outcome:
    event="tool_result", tool="parser_service.parse", status_code, duration_ms, warnings_count
- Parser:
  - log incoming request metadata and outgoing result metadata similarly

Sample data generation (required)
- Provide a script that generates 2 multi-page invoice PDFs locally:
  - sample_invoice_1.pdf: normal totals (no mismatch)
  - sample_invoice_2.pdf: intentionally mismatched subtotal and one outlier unit price
- The PDFs must be readable and consistent enough for demo.
- Provide a simple local hosting option in README:
  - python -m http.server from sample_data/ to serve PDFs on localhost
  - document how to swap localhost for a public URL (e.g., upload to blob)

ACA deployment deliverables (required)
- Dockerfile for parser service.
- A deployment doc + script:
  - build image, push to ACR
  - create/update ACA with:
    - env vars
    - ingress external enabled
    - GPU settings placeholder variables (ACA_GPU_SKU etc.)
- Keep GPU configuration flexible with placeholders and comments.

Orchestrator runnable modes (required)
- CLI mode:
  - python -m orchestrator.app --pdf-url ... --prompt "..."
- Optional: small FastAPI endpoint for orchestrator if you want, but CLI is enough.
- Orchestrator should print:
  - trace_id, request_id
  - anomalies summary
  - pretty-printed JSON (or write JSON to ./out/ and print path)

Documentation (required)
- Root README:
  - setup venv, install deps
  - run sample data server
  - run parser service locally
  - run orchestrator pointing to local parser
  - how to deploy parser to ACA and rerun orchestrator
- docs/demo_script.md:
  - 2–4 minute talk track with specific “observe” moments (trace_id, spans)
- docs/troubleshooting.md:
  - PDF fetch errors, auth failures, NIM timeouts, OTLP exporter issues

Coding standards
- Use type hints.
- Use Pydantic models for request/response.
- Make code copy-paste runnable with minimal edits (env vars).
- Keep it demo-friendly and not over-engineered.

If any external dependency is uncertain (e.g., exact NIM API schema), implement the integration behind a clean interface with:
- a “mock mode” that simulates NIM output for local testing
- a “real mode” that calls the configured NIM endpoint

Now:
1) State assumptions.
2) Provide a short implementation plan.
3) Generate the full code for the repo (all files), plus docs and scripts.
