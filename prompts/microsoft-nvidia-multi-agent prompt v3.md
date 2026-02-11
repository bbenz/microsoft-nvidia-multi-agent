You are a senior engineer building a demo-quality reference implementation for a Microsoft + NVIDIA hybrid multi-agent workflow.

Your output MUST be production-grade, runnable, deterministic for live demos, and optimized for conference presentations.

If anything is ambiguous, make reasonable assumptions and clearly state them — but do NOT ask clarifying questions unless absolutely required for execution.

========================================================
GOAL
========================================================

Build a single-repo Python project demonstrating a hybrid multi-agent workflow:

1. Coordinator / Orchestrator Agent
   - Python
   - Uses OpenAI Python SDK (Responses API)
   - Runs in Microsoft Foundry Agent Service (but runnable locally)
   - Delegates structured extraction work to a specialist agent

2. GPU Parse Specialist Agent
   - Python web service (FastAPI preferred)
   - Deployable to Azure Container Apps (ACA) with serverless NVIDIA GPUs
   - Calls Nemotron Parse NIM (or mock mode)
   - Performs normalization + anomaly detection

3. Observability + governance
   - End-to-end OpenTelemetry tracing
   - Correlation IDs
   - Audit logging of tool calls

========================================================
DEMO SCENARIO (LOCK THIS IN)
========================================================

User prompt:
“Here’s a PDF URL. Extract the line items into JSON and tell me if anything looks off.”

Flow:
- Orchestrator receives PDF URL
- Calls POST /parse on ACA service
- Parser extracts invoice data via Nemotron Parse
- Parser normalizes + runs anomaly checks
- Orchestrator summarizes anomalies for user
- Full trace visible end-to-end

ONLY implement this invoice parsing scenario.
Ignore image generation or other agent types.

========================================================
LANGUAGE + STACK (LOCKED)
========================================================

Language: Python everywhere  
Repo: single monorepo  
Orchestrator SDK: OpenAI Python SDK using RESPONSES API  
Parser service: FastAPI  
Input: public multi-page PDF URL  
Auth: API key header X-API-Key  
Bounding boxes: normalized [0..1], format {x,y,w,h,page}

========================================================
OUTPUT CONTRACT (LOCKED)
========================================================

Parser returns:

{
  "request_id": "...",
  "trace_id": "...",
  "invoice": {
    "vendor": "...",
    "invoice_date": "...",
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
        "bbox": { "x":0.0,"y":0.0,"w":0.0,"h":0.0,"page":1 }
      }
    ]
  },
  "warnings": [
    { "code": "...", "message": "...", "details": {} }
  ],
  "summary": "human readable summary"
}

========================================================
ANOMALY RULES (LOCKED)
========================================================

Implement exactly:

1) subtotal != sum(line_items.amount)
2) unit_price > 5x median price
3) missing vendor/date/total

Return:
- warnings[]
- human summary string

========================================================
OBSERVABILITY (MANDATORY)
========================================================

Implement OpenTelemetry end-to-end.

Trace propagation:
- W3C traceparent header
- X-Request-Id correlation id

Required spans:
Orchestrator:
- orchestrator.handle_request
- orchestrator.call_parser

Parser:
- parser.handle_parse
- parser.fetch_pdf
- parser.call_nim
- parser.normalize
- parser.anomaly_checks

OTLP exporter configurable via env var.

Also implement structured logs.

========================================================
AUDIT LOGGING (MANDATORY)
========================================================

Log tool usage:

Orchestrator:
- tool_call
- tool_result

Parser:
- request_received
- parse_completed

Never log raw PDF.
Log metadata only.

========================================================
CONFIGURATION (ENV VARS)
========================================================

Everything configurable via env:

OPENAI_API_KEY=
OPENAI_MODEL=
PARSER_URL=
PARSER_API_KEY=
NIM_ENDPOINT=
NIM_MODEL_ID=
NIM_API_KEY=
ACA_GPU_SKU=
OTEL_EXPORTER_OTLP_ENDPOINT=
LOG_LEVEL=

Provide .env.example

========================================================
SAMPLE DATA GENERATION (MANDATORY)
========================================================

Generate deterministic demo PDFs.

Create script:
sample_data/generate_sample_invoice_pdf.py

Must generate:
1) sample_invoice_clean.pdf
2) sample_invoice_anomaly.pdf

These must be deterministic and always produce same totals.

Include multi-page PDF with:
- vendor
- totals
- line items
- one anomaly version with subtotal mismatch + price outlier

========================================================
🚨 DEMO-READY OUTPUT MODE (MANDATORY)
========================================================

THIS SECTION IS CRITICAL.

You MUST make this project deterministic and presentation-ready.

1. Provide a pre-canned public PDF URL variable:
   DEMO_PDF_URL=https://raw.githubusercontent.com/.../sample_invoice_anomaly.pdf

Also allow local hosting:
python -m http.server 8000

2. Provide a one-command demo entry point:

python run_demo.py

This must:
- send request to orchestrator
- call parser
- print formatted output EXACTLY as below

========================================================
CONSOLE OUTPUT FORMAT (LOCK THIS EXACTLY)
========================================================

When demo runs, console output MUST look exactly like this:

--------------------------------------------------
🧾 MULTI-AGENT INVOICE ANALYSIS DEMO
--------------------------------------------------

PDF: <url>
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
ACA DEPLOYMENT OUTPUT
========================================================

Provide:
- Dockerfile
- build/push instructions
- ACA deploy script
- GPU config placeholders

========================================================
DOCUMENTATION OUTPUT
========================================================

Provide:
README.md with:
- local run
- demo run
- ACA deploy
- architecture diagram (ASCII ok)

docs/demo_script.md:
2-minute conference talk track

docs/troubleshooting.md:
common failures

========================================================
DELIVERY FORMAT
========================================================

You must output:

1. Assumptions
2. Implementation plan
3. Full repo file tree
4. All code files
5. Docs
6. Demo script
7. Sample output

Everything must be runnable.

Do NOT summarize.
Generate full implementation.
