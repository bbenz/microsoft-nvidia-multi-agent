# Troubleshooting Guide

## Common Issues

### 1. Parser service fails to start

**Symptom:** `ERROR: Parser service failed to start.`

**Causes & fixes:**
- **Port conflict:** Another process is using port 8001.
  ```bash
  # Check what's using the port
  lsof -i :8001          # macOS/Linux
  netstat -ano | findstr 8001  # Windows
  ```
  Fix: Kill the conflicting process or set `PARSER_PORT=8002`.

- **Missing dependencies:** Run `pip install -r requirements.txt`.

- **Python version:** Requires Python 3.10+. Check with `python --version`.

### 2. "Connection refused" when calling parser

**Symptom:** `httpx.ConnectError: Connection refused`

**Causes:**
- Parser service isn't running. Start it manually:
  ```bash
  uvicorn parser_service.main:app --host 127.0.0.1 --port 8001
  ```
- Firewall blocking localhost connections (rare on dev machines).

### 3. PDF URL returns 404

**Symptom:** `httpx.HTTPStatusError: 404`

**Fix:** Make sure you're serving the sample PDFs:
```bash
# Generate PDFs first
python sample_data/generate_sample_invoice_pdf.py

# Serve them
cd sample_data && python -m http.server 8000
```

Then use: `DEMO_PDF_URL=http://localhost:8000/sample_invoice_anomaly.pdf`

### 4. "Invalid or missing API key" (401)

**Symptom:** Parser returns HTTP 401.

**Fix:** Ensure `PARSER_API_KEY` matches between the client and server:
```bash
# In .env or environment
PARSER_API_KEY=demo-api-key-change-me
```

### 5. Agent mode: "OPENAI_API_KEY required"

**Symptom:** Error when running `python run_demo.py --mode agent`

**Fix:** Set your OpenAI API key:
```bash
export OPENAI_API_KEY=sk-your-key-here
# Or add to .env file
```

### 6. OpenTelemetry traces not appearing

**Symptom:** No traces in Jaeger/collector.

**Causes:**
- `OTEL_EXPORTER_OTLP_ENDPOINT` not set. Add to your `.env`:
  ```
  OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
  ```
- OTLP collector not running. Start Jaeger all-in-one:
  ```bash
  docker run -d --name jaeger \
    -p 4317:4317 \
    -p 16686:16686 \
    jaegertracing/all-in-one:latest
  ```
  Then open http://localhost:16686.

### 7. NIM endpoint errors

**Symptom:** HTTP errors when `NIM_ENDPOINT` is set.

**Fixes:**
- Verify the NIM endpoint is reachable: `curl $NIM_ENDPOINT/v1/models`
- Check `NIM_API_KEY` is correct.
- For demo purposes, leave `NIM_ENDPOINT` blank to use mock mode.

### 8. Docker build fails

**Symptom:** Build errors when creating the container image.

**Fixes:**
- Ensure Docker is running.
- Check you're in the project root (where `Dockerfile` is).
- Try: `docker build --no-cache -t gpu-parse-agent .`

### 9. ACA deployment: GPU not available

**Symptom:** Container starts but no GPU acceleration.

**Fix:** GPU workload profiles are region-specific. Check availability:
```bash
az containerapp env workload-profile list-supported \
  --location eastus2
```

If your region doesn't support GPUs, the app still works — it just runs on CPU (which is fine for mock mode / demo).

### 10. Windows-specific: Unicode output garbled

**Symptom:** Emoji characters display incorrectly in terminal.

**Fix:** Use Windows Terminal (not cmd.exe) and ensure UTF-8:
```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001
```

## Getting Help

1. Check the logs: `LOG_LEVEL=DEBUG python run_demo.py`
2. Run parser standalone: `uvicorn parser_service.main:app --port 8001 --log-level debug`
3. Test parser health: `curl http://localhost:8001/health`
