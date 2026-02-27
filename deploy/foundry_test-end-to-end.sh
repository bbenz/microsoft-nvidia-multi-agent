#!/usr/bin/env bash
# ============================================================
# End-to-End Test for Multi-Agent Deployment
# ============================================================
#
# Tests everything deployed by:
#   1. deploy/aca_deploy.sh   — GPU Parse Specialist on ACA
#   2. deploy/foundry_deploy.sh — Azure OpenAI + AI Foundry
#
# Tests performed:
#   T1. ACA /health endpoint
#   T2. ACA /parse endpoint (sample invoice)
#   T3. Azure OpenAI connectivity (chat completion)
#   T4. Full agent-mode pipeline (orchestrator → parser)
#
# Usage:
#   chmod +x deploy/foundry_test-end-to-end.sh
#   ./deploy/foundry_test-end-to-end.sh
#
# Environment variables (override defaults):
#   RESOURCE_GROUP, ACA_APP_NAME, PARSER_API_KEY,
#   OPENAI_RESOURCE_NAME
# ============================================================

set -euo pipefail

# ---- Helpers ----
strip_cr() { tr -d '\r'; }

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Colour

pass() { echo -e "  ${GREEN}✓ PASS${NC}: $1"; }
fail() { echo -e "  ${RED}✗ FAIL${NC}: $1"; FAILURES=$((FAILURES + 1)); }
warn() { echo -e "  ${YELLOW}⚠ WARN${NC}: $1"; }
info() { echo -e "  $1"; }

FAILURES=0
TESTS=0

run_test() {
  local name="$1"
  TESTS=$((TESTS + 1))
  echo ""
  echo "--------------------------------------------"
  echo "  T${TESTS}. ${name}"
  echo "--------------------------------------------"
}

# ---- Load .env if present (before defaults) ----
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

# ---- Activate venv if present ----
if [[ -f .venv/bin/activate ]]; then
  source .venv/bin/activate
  info "Using Python venv: $(which python3)"
fi

echo "============================================"
echo "  End-to-End Test Suite"
echo "============================================"
echo "Resource Group  : ${RESOURCE_GROUP}"
echo "ACA App         : ${ACA_APP_NAME}"
echo "OpenAI Resource : ${OPENAI_RESOURCE_NAME}"
echo "============================================"

# ---- Sync ACA secrets to match .env ----
echo ""
echo "Syncing ACA secrets..."
NIM_ENDPOINT_VAL="${NIM_ENDPOINT:-placeholder}"
NIM_API_KEY_VAL="${NIM_API_KEY:-placeholder}"
PARSER_API_KEY_VAL="${PARSER_API_KEY:-placeholder}"

az containerapp secret set \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --secrets "nim-endpoint=${NIM_ENDPOINT_VAL}" \
            "nim-api-key=${NIM_API_KEY_VAL}" \
            "parser-api-key=${PARSER_API_KEY_VAL}" \
  --output none 2>/dev/null || warn "Could not sync ACA secrets"

# Wait for ACA to settle after secret change (triggers container restart)
echo "Waiting for ACA container to restart after secret sync..."
for i in $(seq 1 12); do
  sleep 5
  HC=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
    "https://$(az containerapp show --name "${ACA_APP_NAME}" --resource-group "${RESOURCE_GROUP}" \
      --query 'properties.configuration.ingress.fqdn' -o tsv 2>/dev/null | strip_cr)/health" 2>/dev/null | strip_cr || true)
  if [[ "${HC}" == "200" ]]; then
    echo "ACA is healthy."
    break
  fi
  echo "  Attempt ${i}/12 — waiting..."
done

# ---- Resolve ACA URL ----
echo ""
echo "Resolving ACA application URL..."
ACA_FQDN=$(az containerapp show \
  --name "${ACA_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null | strip_cr || true)

if [[ -z "${ACA_FQDN}" ]]; then
  echo "WARNING: Could not resolve ACA app URL. ACA tests will be skipped."
  echo "         Did you run deploy/aca_deploy.sh first?"
  ACA_URL=""
else
  ACA_URL="https://${ACA_FQDN}"
  info "ACA URL: ${ACA_URL}"
fi

# ================================================================
# T1. ACA Health Check
# ================================================================
run_test "ACA Health Check"

if [[ -z "${ACA_URL}" ]]; then
  warn "Skipped — ACA URL not available"
else
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 15 "${ACA_URL}/health" 2>/dev/null | strip_cr || echo "000")
  if [[ "${HTTP_CODE}" == "200" ]]; then
    pass "/health returned 200"
  else
    fail "/health returned HTTP ${HTTP_CODE}"
  fi
fi

# ================================================================
# T2. ACA Parse Endpoint
# ================================================================
run_test "ACA Parse Endpoint"

if [[ -z "${ACA_URL}" ]]; then
  warn "Skipped — ACA URL not available"
else
  # Must use a publicly accessible URL (not localhost) since the parser runs in ACA
  SAMPLE_PDF_URL="https://raw.githubusercontent.com/bbenz/microsoft-nvidia-multi-agent/main/sample_data/sample_invoice_anomaly.pdf"

  PARSE_RESPONSE=$(curl -s --max-time 120 \
    -X POST "${ACA_URL}/parse" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${PARSER_API_KEY}" \
    -d "{\"pdf_url\": \"${SAMPLE_PDF_URL}\"}" 2>/dev/null || echo "")

  if [[ -z "${PARSE_RESPONSE}" ]]; then
    fail "/parse returned no response"
  elif echo "${PARSE_RESPONSE}" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'invoice' in d" 2>/dev/null; then
    pass "/parse returned valid invoice JSON"
    # Show quick summary
    VENDOR=$(echo "${PARSE_RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin)['invoice']['vendor'])" 2>/dev/null || echo "unknown")
    WARNINGS=$(echo "${PARSE_RESPONSE}" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('warnings',[])))" 2>/dev/null || echo "?")
    info "Vendor: ${VENDOR}, Warnings: ${WARNINGS}"
    # Display each warning message
    if [[ "${WARNINGS}" =~ ^[0-9]+$ ]] && [[ "${WARNINGS}" -gt 0 ]]; then
      echo "${PARSE_RESPONSE}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for w in data.get('warnings', []):
    msg = w if isinstance(w, str) else w.get('message', w.get('msg', str(w)))
    print(f'  ⚠ {msg}')
" 2>/dev/null || true
    fi
  else
    fail "/parse response missing 'invoice' key"
    info "Response: ${PARSE_RESPONSE:0:200}"
  fi
fi

# ================================================================
# T3. Azure OpenAI Connectivity
# ================================================================
run_test "Azure OpenAI Connectivity"

# Get endpoint and key
OPENAI_ENDPOINT=$(az cognitiveservices account show \
  --name "${OPENAI_RESOURCE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.endpoint" -o tsv 2>/dev/null | strip_cr || true)

OPENAI_KEY=$(az cognitiveservices account keys list \
  --name "${OPENAI_RESOURCE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "key1" -o tsv 2>/dev/null | strip_cr || true)

if [[ -z "${OPENAI_ENDPOINT}" || -z "${OPENAI_KEY}" ]]; then
  warn "Skipped — could not retrieve Azure OpenAI credentials. Did you run deploy/foundry_deploy.sh?"
else
  API_VERSION="2024-12-01-preview"
  CHAT_URL="${OPENAI_ENDPOINT}openai/deployments/${OPENAI_DEPLOYMENT_NAME}/chat/completions?api-version=${API_VERSION}"

  CHAT_RESPONSE=$(curl -s --max-time 30 \
    -X POST "${CHAT_URL}" \
    -H "Content-Type: application/json" \
    -H "api-key: ${OPENAI_KEY}" \
    -d '{
      "messages": [{"role":"user","content":"Say hello in exactly 3 words."}],
      "max_tokens": 20
    }' 2>/dev/null || echo "")

  if [[ -z "${CHAT_RESPONSE}" ]]; then
    fail "No response from Azure OpenAI"
  elif echo "${CHAT_RESPONSE}" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'choices' in d" 2>/dev/null; then
    pass "Azure OpenAI ${OPENAI_DEPLOYMENT_NAME} responded"
    REPLY=$(echo "${CHAT_RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])" 2>/dev/null || echo "")
    info "Model replied: ${REPLY}"
  elif echo "${CHAT_RESPONSE}" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'error' in d" 2>/dev/null; then
    ERR=$(echo "${CHAT_RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin)['error']['message'])" 2>/dev/null || echo "unknown")
    fail "Azure OpenAI error: ${ERR}"
  else
    fail "Unexpected response from Azure OpenAI"
    info "Response: ${CHAT_RESPONSE:0:200}"
  fi
fi

# ================================================================
# T4. Full Agent Pipeline (run_demo.py --mode agent)
# ================================================================
run_test "Full Agent Pipeline (orchestrator → parser)"

if [[ -z "${ACA_URL}" ]]; then
  warn "Skipped — ACA URL not available (parser not reachable)"
elif [[ -z "${OPENAI_ENDPOINT}" || -z "${OPENAI_KEY}" ]]; then
  warn "Skipped — Azure OpenAI credentials not available"
else
  # Check Python deps are available
  if ! python3 -c "import httpx, openai, dotenv" 2>/dev/null; then
    fail "Missing Python dependencies (httpx, openai, python-dotenv). Run: pip install -r requirements.txt"
  else
  # Must use a publicly accessible URL (not localhost) since the parser runs in ACA
  SAMPLE_PDF_URL="https://raw.githubusercontent.com/bbenz/microsoft-nvidia-multi-agent/main/sample_data/sample_invoice_anomaly.pdf"

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
      --pdf-url "${SAMPLE_PDF_URL}" 2>&1 || true)

  if echo "${AGENT_OUTPUT}" | grep -q "AGENT SUMMARY"; then
    pass "Agent pipeline completed — summary generated"
    # Extract summary lines (between AGENT SUMMARY and the next separator)
    SUMMARY=$(echo "${AGENT_OUTPUT}" | sed -n '/AGENT SUMMARY/,/----/{/AGENT SUMMARY/d;/----/d;p}' | head -5)
    if [[ -n "${SUMMARY}" ]]; then
      info "Summary preview:"
      echo "${SUMMARY}" | while IFS= read -r line; do
        info "  ${line}"
      done
    fi
  elif echo "${AGENT_OUTPUT}" | grep -q "EXTRACTED TOTALS"; then
    warn "Pipeline ran but may have fallen back to direct mode"
    info "Output contained EXTRACTED TOTALS but no AGENT SUMMARY"
  elif echo "${AGENT_OUTPUT}" | grep -qi "error"; then
    fail "Agent pipeline failed"
    # Show last few relevant lines
    echo "${AGENT_OUTPUT}" | grep -i "error" | tail -5 | while IFS= read -r line; do
      info "  ${line}"
    done
  else
    fail "Agent pipeline produced unexpected output"
    info "Output: ${AGENT_OUTPUT:0:300}"
  fi
  fi
fi

# ================================================================
# Summary
# ================================================================
echo ""
echo "============================================"
echo "  Test Results"
echo "============================================"
if [[ ${FAILURES} -eq 0 ]]; then
  echo -e "  ${GREEN}All ${TESTS} tests passed.${NC}"
else
  echo -e "  ${RED}${FAILURES} of ${TESTS} tests failed.${NC}"
fi
echo "============================================"

exit "${FAILURES}"
