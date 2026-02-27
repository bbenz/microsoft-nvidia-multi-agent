#!/usr/bin/env bash
# ============================================================
# Verbose Demo: Process All Invoices End-to-End
# ============================================================
#
# Runs each sample invoice through the full multi-agent pipeline,
# displaying every component interaction in detail:
#
#   1. Parser Service (FastAPI on Azure Container Apps)
#      → Downloads PDF
#      → Sends pages to NVIDIA Nemotron Parse NIM for extraction
#      → Normalizes extracted data
#      → Runs anomaly detection rules
#
#   2. Orchestrator Agent (OpenAI GPT-4o via Azure AI Foundry)
#      → Receives invoice PDF URL
#      → Calls parse_invoice tool (→ Parser Service)
#      → Analyzes results and generates summary
#
# Usage:
#   chmod +x deploy/demo-run-on-all-docs.sh
#   ./deploy/demo-run-on-all-docs.sh
#
# Environment variables (loaded from .env, or override):
#   RESOURCE_GROUP, ACA_APP_NAME, PARSER_API_KEY,
#   OPENAI_RESOURCE_NAME, OPENAI_DEPLOYMENT_NAME
# ============================================================

set -euo pipefail

# ---- Helpers ----
strip_cr() { tr -d '\r'; }

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

banner()  { echo -e "\n${BOLD}${CYAN}$1${NC}"; }
step()    { echo -e "  ${CYAN}→${NC} $1"; }
detail()  { echo -e "    ${DIM}$1${NC}"; }
ok()      { echo -e "  ${GREEN}✓${NC} $1"; }
warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }
error()   { echo -e "  ${RED}✗${NC} $1"; }
line()    { echo "────────────────────────────────────────────────────────────"; }

# ---- Load .env ----
if [[ -f .env ]]; then
  set -a
  source <(sed 's/\r$//' .env)
  set +a
fi

# ---- Configuration ----
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-multi-agent-demo}"
ACA_APP_NAME="${ACA_APP_NAME:-gpu-parse-agent}"
PARSER_API_KEY="${PARSER_API_KEY:-demo-api-key-change-me}"
OPENAI_RESOURCE_NAME="${OPENAI_RESOURCE_NAME:-multi-agent-openai}"
OPENAI_DEPLOYMENT_NAME="${OPENAI_DEPLOYMENT_NAME:-gpt-4o}"

# GitHub raw base URL for sample PDFs
GITHUB_RAW_BASE="https://raw.githubusercontent.com/bbenz/microsoft-nvidia-multi-agent/main/sample_data"

# All sample invoices to process
INVOICES=(
  "sample_invoice_clean.pdf"
  "sample_invoice_anomaly.pdf"
)

# ---- Activate venv ----
if [[ -f .venv/bin/activate ]]; then
  source .venv/bin/activate
fi

# ================================================================
echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     Multi-Agent Invoice Processing Demo                  ║${NC}"
echo -e "${BOLD}║     NVIDIA Nemotron Parse + Azure OpenAI GPT-4o          ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Resource Group  : ${RESOURCE_GROUP}"
echo "  ACA App         : ${ACA_APP_NAME}"
echo "  OpenAI Resource : ${OPENAI_RESOURCE_NAME}"
echo "  OpenAI Model    : ${OPENAI_DEPLOYMENT_NAME}"
echo "  Invoices        : ${#INVOICES[@]} documents"

# ================================================================
# Resolve infrastructure
# ================================================================
banner "STEP 0: Resolving Infrastructure"
line

step "Looking up Azure Container Apps endpoint..."
ACA_FQDN=$(az containerapp show \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null | strip_cr || true)

if [[ -z "${ACA_FQDN}" ]]; then
  error "Could not resolve ACA URL. Run deploy/aca_deploy.sh first."
  exit 1
fi
ACA_URL="https://${ACA_FQDN}"
ok "Parser Service URL: ${ACA_URL}"
detail "This FastAPI service runs on Azure Container Apps with GPU support."
detail "It hosts the /parse endpoint that calls NVIDIA Nemotron Parse NIM."

step "Checking Parser Service health..."
HC=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "${ACA_URL}/health" 2>/dev/null | strip_cr || echo "000")
if [[ "${HC}" == "200" ]]; then
  HEALTH_BODY=$(curl -s --max-time 10 "${ACA_URL}/health" 2>/dev/null || echo "{}")
  MOCK_MODE=$(echo "${HEALTH_BODY}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('mock_mode','unknown'))" 2>/dev/null || echo "unknown")
  ok "Parser Service is healthy (mock_mode=${MOCK_MODE})"
else
  error "Parser Service returned HTTP ${HC}. Is the container running?"
  exit 1
fi

step "Retrieving Azure OpenAI credentials..."
OPENAI_ENDPOINT=$(az cognitiveservices account show \
  --name "${OPENAI_RESOURCE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.endpoint" -o tsv 2>/dev/null | strip_cr || true)

OPENAI_KEY=$(az cognitiveservices account keys list \
  --name "${OPENAI_RESOURCE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "key1" -o tsv 2>/dev/null | strip_cr || true)

if [[ -z "${OPENAI_ENDPOINT}" || -z "${OPENAI_KEY}" ]]; then
  error "Could not retrieve Azure OpenAI credentials. Run deploy/foundry_deploy.sh first."
  exit 1
fi
ok "Azure OpenAI endpoint: ${OPENAI_ENDPOINT}"
detail "Model deployment: ${OPENAI_DEPLOYMENT_NAME} (GPT-4o)"

TOTAL_DOCS=${#INVOICES[@]}
PROCESSED=0
FAILED=0

# ================================================================
# Process each invoice
# ================================================================
for idx in "${!INVOICES[@]}"; do
  DOC="${INVOICES[$idx]}"
  DOC_NUM=$((idx + 1))
  PDF_URL="${GITHUB_RAW_BASE}/${DOC}"

  echo ""
  echo ""
  echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║  Document ${DOC_NUM}/${TOTAL_DOCS}: ${DOC}${NC}"
  echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo "  PDF URL: ${PDF_URL}"

  # ----------------------------------------------------------
  # Phase 1: Parser Service — Direct /parse call
  # ----------------------------------------------------------
  banner "Phase 1: Parser Service (NVIDIA Nemotron Parse)"
  line

  step "[Parser] Sending POST /parse request to ACA..."
  detail "The Parser Service will:"
  detail "  1. Download the PDF from GitHub"
  detail "  2. Convert each page to a PNG image (300 DPI via pypdfium2)"
  detail "  3. Send each page to NVIDIA Nemotron Parse NIM API"
  detail "     Model: nvidia/nemotron-parse"
  detail "     Endpoint: https://integrate.api.nvidia.com/v1/chat/completions"
  detail "  4. Merge results from all pages"
  detail "  5. Extract structured fields (vendor, dates, line items, totals)"
  detail "  6. Normalize data (round amounts, default currency to USD)"
  detail "  7. Run anomaly detection rules"
  echo ""

  PARSE_START=$(date +%s)
  PARSE_RESPONSE=$(curl -s --max-time 120 \
    -X POST "${ACA_URL}/parse" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${PARSER_API_KEY}" \
    -d "{\"pdf_url\": \"${PDF_URL}\"}" 2>/dev/null || echo "")
  PARSE_END=$(date +%s)
  PARSE_DURATION=$((PARSE_END - PARSE_START))

  if [[ -z "${PARSE_RESPONSE}" ]]; then
    error "[Parser] No response from /parse endpoint (timeout after ${PARSE_DURATION}s)"
    FAILED=$((FAILED + 1))
    continue
  fi

  # Validate response
  HAS_INVOICE=$(echo "${PARSE_RESPONSE}" | python3 -c "import sys,json; d=json.load(sys.stdin); print('yes' if 'invoice' in d else 'no')" 2>/dev/null || echo "no")
  if [[ "${HAS_INVOICE}" != "yes" ]]; then
    error "[Parser] Response missing 'invoice' key"
    detail "Response: ${PARSE_RESPONSE:0:300}"
    FAILED=$((FAILED + 1))
    continue
  fi

  ok "[Parser] Invoice extracted successfully (${PARSE_DURATION}s)"
  echo ""

  # Display extracted invoice details
  step "[Parser] Extracted Invoice Data:"
  echo "${PARSE_RESPONSE}" | python3 -c "
import sys, json

data = json.load(sys.stdin)
inv = data['invoice']
warnings = data.get('warnings', [])
summary = data.get('summary', '')

print(f'    ┌─────────────────────────────────────────────────────')
print(f'    │ Vendor:         {inv[\"vendor\"]}')
print(f'    │ Invoice Number: {inv[\"invoice_number\"]}')
print(f'    │ Invoice Date:   {inv[\"invoice_date\"]}')
print(f'    │ Currency:       {inv[\"currency\"]}')
print(f'    ├─────────────────────────────────────────────────────')
print(f'    │ Line Items:')
for i, li in enumerate(inv.get('line_items', []), 1):
    desc = li['description']
    qty = li['quantity']
    price = li['unit_price']
    amt = li['amount']
    print(f'    │   {i}. {desc:<30s} {qty:>3d} × \${price:>8.2f} = \${amt:>9.2f}')
print(f'    ├─────────────────────────────────────────────────────')
print(f'    │ Subtotal:  \${inv[\"subtotal\"]:>10.2f}')
print(f'    │ Tax:       \${inv[\"tax\"]:>10.2f}')
print(f'    │ Total:     \${inv[\"total\"]:>10.2f}')
print(f'    └─────────────────────────────────────────────────────')
" 2>/dev/null || detail "(could not format invoice)"

  echo ""

  # Display anomaly detection results
  step "[Anomaly Detection] Checking for anomalies..."
  detail "Rules applied:"
  detail "  Rule 1: Subtotal vs sum of line item amounts"
  detail "  Rule 2: Unit price outlier (> 5× median price)"
  detail "  Rule 3: Missing required fields (vendor, date, total)"
  echo ""

  WARN_COUNT=$(echo "${PARSE_RESPONSE}" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('warnings',[])))" 2>/dev/null || echo "0")

  if [[ "${WARN_COUNT}" == "0" ]]; then
    ok "[Anomaly Detection] No anomalies detected — invoice looks clean"
  else
    warning "[Anomaly Detection] ${WARN_COUNT} anomaly/anomalies detected:"
    echo "${PARSE_RESPONSE}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for w in data.get('warnings', []):
    code = w.get('code', 'UNKNOWN')
    msg = w.get('message', str(w))
    details = w.get('details', {})
    print(f'    ⚠ [{code}] {msg}')
    if details:
        for k, v in details.items():
            print(f'      └─ {k}: {v}')
" 2>/dev/null || true
  fi

  # Display parser summary
  PARSER_SUMMARY=$(echo "${PARSE_RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('summary',''))" 2>/dev/null || echo "")
  if [[ -n "${PARSER_SUMMARY}" ]]; then
    echo ""
    step "[Parser] Summary:"
    echo "${PARSER_SUMMARY}" | while IFS= read -r sline; do
      detail "${sline}"
    done
  fi

  # ----------------------------------------------------------
  # Phase 2: Orchestrator Agent — GPT-4o analysis
  # ----------------------------------------------------------
  echo ""
  banner "Phase 2: Orchestrator Agent (Azure OpenAI GPT-4o)"
  line

  step "[Orchestrator] Starting agent pipeline..."
  detail "The Orchestrator Agent will:"
  detail "  1. Connect to Azure OpenAI (${OPENAI_DEPLOYMENT_NAME})"
  detail "  2. Send the PDF URL to the model with a parse_invoice tool"
  detail "  3. GPT-4o decides to call the parse_invoice tool"
  detail "  4. Orchestrator executes: POST ${ACA_URL}/parse"
  detail "  5. Tool result (invoice + warnings) sent back to GPT-4o"
  detail "  6. GPT-4o analyzes the invoice and generates a summary"
  echo ""

  # Check Python deps
  if ! python3 -c "import httpx, openai, dotenv" 2>/dev/null; then
    error "[Orchestrator] Missing Python dependencies. Run: pip install -r requirements.txt"
    FAILED=$((FAILED + 1))
    continue
  fi

  AGENT_START=$(date +%s)
  AGENT_OUTPUT=$(OPENAI_API_KEY="${OPENAI_KEY}" \
    OPENAI_API_BASE="${OPENAI_ENDPOINT}" \
    OPENAI_API_TYPE=azure \
    OPENAI_API_VERSION="2025-03-01-preview" \
    OPENAI_MODEL="${OPENAI_DEPLOYMENT_NAME}" \
    PARSER_URL="${ACA_URL}" \
    PARSER_API_KEY="${PARSER_API_KEY}" \
    python3 run_demo.py \
      --mode agent \
      --no-parser \
      --pdf-url "${PDF_URL}" 2>&1 || true)
  AGENT_END=$(date +%s)
  AGENT_DURATION=$((AGENT_END - AGENT_START))

  if echo "${AGENT_OUTPUT}" | grep -q "AGENT SUMMARY"; then
    ok "[Orchestrator] Agent pipeline completed (${AGENT_DURATION}s)"
    echo ""

    # Show extracted totals
    TOTALS=$(echo "${AGENT_OUTPUT}" | sed -n '/EXTRACTED TOTALS/,/----/{/EXTRACTED TOTALS/d;/----/d;p}' | head -10)
    if [[ -n "${TOTALS}" ]]; then
      step "[Orchestrator] Extracted Totals (from agent output):"
      echo "${TOTALS}" | while IFS= read -r tline; do
        [[ -n "${tline}" ]] && detail "${tline}"
      done
      echo ""
    fi

    # Show anomalies from agent
    ANOMALIES=$(echo "${AGENT_OUTPUT}" | sed -n '/ANOMALIES/,/----/{/ANOMALIES/d;/----/d;p}' | head -10)
    if [[ -n "${ANOMALIES}" ]]; then
      step "[Orchestrator] Anomalies Detected (from agent output):"
      echo "${ANOMALIES}" | while IFS= read -r aline; do
        [[ -n "${aline}" ]] && detail "${aline}"
      done
      echo ""
    fi

    # Show agent's AI-generated summary
    SUMMARY=$(echo "${AGENT_OUTPUT}" | sed -n '/AGENT SUMMARY/,/----/{/AGENT SUMMARY/d;/----/d;p}' | head -20)
    if [[ -n "${SUMMARY}" ]]; then
      step "[Orchestrator] GPT-4o Agent Summary:"
      echo -e "    ${CYAN}┌─────────────────────────────────────────────────────${NC}"
      echo "${SUMMARY}" | while IFS= read -r sline; do
        [[ -n "${sline}" ]] && echo -e "    ${CYAN}│${NC} ${sline}"
      done
      echo -e "    ${CYAN}└─────────────────────────────────────────────────────${NC}"
    fi

    PROCESSED=$((PROCESSED + 1))
  elif echo "${AGENT_OUTPUT}" | grep -qi "error"; then
    error "[Orchestrator] Agent pipeline failed (${AGENT_DURATION}s)"
    echo "${AGENT_OUTPUT}" | grep -i "error" | tail -5 | while IFS= read -r eline; do
      detail "${eline}"
    done
    FAILED=$((FAILED + 1))
  else
    error "[Orchestrator] Unexpected agent output (${AGENT_DURATION}s)"
    detail "${AGENT_OUTPUT:0:300}"
    FAILED=$((FAILED + 1))
  fi

done

# ================================================================
# Final Summary
# ================================================================
echo ""
echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Demo Complete                                           ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Documents processed: ${PROCESSED}/${TOTAL_DOCS}"
if [[ ${FAILED} -gt 0 ]]; then
  echo -e "  ${RED}Failed: ${FAILED}${NC}"
fi
echo ""
echo "  Components used:"
echo "    • Parser Service    — Azure Container Apps (GPU)"
echo "    • NVIDIA NIM        — Nemotron Parse (document extraction)"
echo "    • Azure OpenAI      — GPT-4o (agent reasoning)"
echo "    • Anomaly Detection — Rule-based validation"
echo ""

if [[ ${FAILED} -eq 0 ]]; then
  echo -e "  ${GREEN}All ${TOTAL_DOCS} documents processed successfully.${NC}"
else
  echo -e "  ${RED}${FAILED} of ${TOTAL_DOCS} documents had errors.${NC}"
fi
echo ""

exit "${FAILED}"
