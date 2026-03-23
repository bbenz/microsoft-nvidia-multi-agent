# Java Orchestrator — Microsoft + NVIDIA Multi-Agent Demo

A Java-based orchestrator using **Spring Boot 3.4** and **LangChain4j** that is a drop-in replacement for the Python orchestrator. It calls the existing Python parser service to extract invoice data, detect anomalies, and present results — with full OpenTelemetry tracing and structured audit logging.

---

## Architecture

```
┌─────────────────────────────────────┐
│         Java Orchestrator           │
│  (Spring Boot + LangChain4j)        │
│                                     │
│  Direct Mode: call parser directly  │
│  Agent Mode:  LLM → tool call       │
│               → parser → summary    │
└──────────────┬──────────────────────┘
               │  POST /parse
               │  X-API-Key, X-Request-Id, traceparent
               ▼
┌─────────────────────────────────────┐
│     Python Parser Service           │
│  (FastAPI — existing, unchanged)    │
│                                     │
│  Local: http://localhost:8001       │
│  ACA:   https://...azurecontainer   │
│         apps.io                     │
└─────────────────────────────────────┘
```

---

## Prerequisites

- **Java 21+** (e.g., Eclipse Temurin, Microsoft Build of OpenJDK)
- **Maven 3.9+**
- **Python 3.10+** (for the parser service)
- **Docker** (optional, for container builds)

---

## Quick Start

### 1. Build

```bash
cd javaorchestrator
mvn clean package -DskipTests
```

### 2. Run (Direct Mode — No LLM Required)

Start the parser service and PDF server in separate terminals first:

```bash
# Terminal 1: Parser service (from repo root)
cd ..
uvicorn parser_service.main:app --port 8001

# Terminal 2: Serve sample PDFs (from repo root)
cd ..
python -m http.server 8000 -d sample_data

# Terminal 3: Java orchestrator
cd javaorchestrator
mvn spring-boot:run -Dspring-boot.run.profiles=demo
```

### 3. Run (Agent Mode — Requires OpenAI Key)

```bash
cd javaorchestrator
mvn spring-boot:run -Dspring-boot.run.profiles=demo \
  -Dspring-boot.run.arguments="--orchestrator.demo.mode=agent"
```

Or with a pre-built JAR:

```bash
java -jar target/orchestrator-0.1.0.jar \
  --spring.profiles.active=demo \
  --orchestrator.demo.mode=agent
```

---

## Configuration

All settings are controlled via environment variables, the same ones used by the Python orchestrator. The Java app loads `../.env` from the repo root automatically.

| Env Variable | Default | Description |
|---|---|---|
| `OPENAI_API_KEY` | *(empty)* | OpenAI / Azure OpenAI API key (agent mode only) |
| `OPENAI_MODEL` | `gpt-4o` | Model name or deployment name |
| `OPENAI_API_BASE` | *(empty)* | Custom base URL (for Azure AI Foundry endpoint) |
| `PARSER_URL` | `http://localhost:8001` | Parser service URL (local or ACA) |
| `PARSER_API_KEY` | `demo-api-key-change-me` | API key for parser auth |
| `PARSER_TIMEOUT` | `120` | HTTP timeout in seconds |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | *(empty)* | OTLP gRPC endpoint (e.g., `http://localhost:4317`) |
| `LOG_LEVEL` | `INFO` | Logging level |
| `DEMO_PDF_URL` | `http://localhost:8000/sample_invoice_anomaly.pdf` | PDF URL for demo |
| `DEMO_MODE` | `direct` | `direct` or `agent` |

---

## Deployment Topologies

| Topology | Orchestrator | Parser | OpenAI | Key Env Vars |
|---|---|---|---|---|
| **Fully Local** | Dev machine | `localhost:8001` | Direct API | `PARSER_URL=http://localhost:8001` |
| **Hybrid** | Dev machine | ACA (remote) | Direct or Foundry | `PARSER_URL=https://...azurecontainerapps.io` |
| **Fully Cloud** | ACA container | ACA with GPU | Azure AI Foundry | `PARSER_URL=https://...`, `OPENAI_API_BASE=https://...` |

No code changes required — topology is controlled entirely by env vars.

---

## Running Locally with the Python Parser Service

### Step-by-step

**Terminal 1 — Parser Service:**
```bash
cd <repo-root>
pip install -r requirements.txt  # first time only
uvicorn parser_service.main:app --port 8001
```
Expected: `INFO: Uvicorn running on http://127.0.0.1:8001`

**Terminal 2 — PDF Server:**
```bash
cd <repo-root>
python -m http.server 8000 -d sample_data
```
Expected: `Serving HTTP on 0.0.0.0 port 8000`

**Terminal 3 — Java Orchestrator:**
```bash
cd <repo-root>/javaorchestrator
mvn spring-boot:run -Dspring-boot.run.profiles=demo
```

Expected output:
```
--------------------------------------------------
🧾 MULTI-AGENT INVOICE ANALYSIS DEMO
--------------------------------------------------

PDF: http://localhost:8000/sample_invoice_anomaly.pdf
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
1. Subtotal mismatch: ...
2. High unit price outlier: ...

--------------------------------------------------
🧠 AGENT SUMMARY
--------------------------------------------------
The invoice was parsed successfully. ...

--------------------------------------------------
🔭 OBSERVABILITY
--------------------------------------------------
Trace exported via OpenTelemetry
Use trace_id above in your dashboard to view full agent chain.

Demo complete.
--------------------------------------------------
```

---

## Running Against Parser on ACA + OpenAI via Foundry

Once the parser is deployed to ACA and GPT-4o is deployed via Foundry:

```bash
# Env vars are set by deploy/foundry_deploy.sh and deploy/aca_deploy.sh
# Or set them manually:
export PARSER_URL=https://gpu-parse-agent.<env>.azurecontainerapps.io
export OPENAI_API_BASE=https://<resource>.openai.azure.com/
export OPENAI_API_KEY=<your-key>

cd javaorchestrator
mvn spring-boot:run -Dspring-boot.run.profiles=demo \
  -Dspring-boot.run.arguments="--orchestrator.demo.mode=agent"
```

Validate with the existing test suite:
```bash
cd <repo-root>
./deploy/foundry_test-end-to-end.sh
```

---

## Direct Mode vs Agent Mode

| Feature | Direct Mode | Agent Mode |
|---|---|---|
| LLM required | No | Yes (OPENAI_API_KEY) |
| Deterministic | Yes | No (LLM summary varies) |
| Best for | Keynote demos, testing | Full agent demo |
| Parser call | Direct HTTP | Via LangChain4j tool call |
| Summary source | Parser's built-in summary | LLM-generated summary |

---

## Docker Build and Run

```bash
cd javaorchestrator
docker build -t java-orchestrator .
docker run --env-file ../.env --network host java-orchestrator
```

For agent mode:
```bash
docker run --env-file ../.env --network host \
  -e SPRING_PROFILES_ACTIVE=demo \
  -e DEMO_MODE=agent \
  java-orchestrator
```

---

## Deploying to Azure AI Foundry

### 1. Provision Azure AI Resources

Use the existing deployment script:

```bash
cd <repo-root>
./deploy/foundry_deploy.sh
```

This creates an Azure AI Foundry Hub, Project, and GPT-4o deployment, then writes `OPENAI_API_KEY`, `OPENAI_API_BASE`, and `OPENAI_MODEL` to your `.env` file.

### 2. Run Java Orchestrator Against Foundry

```bash
cd javaorchestrator
mvn spring-boot:run -Dspring-boot.run.profiles=demo \
  -Dspring-boot.run.arguments="--orchestrator.demo.mode=agent"
```

The `.env` already contains the Foundry endpoint and key.

### 3. Deploy as Container to ACA

```bash
cd javaorchestrator
docker build -t java-orchestrator .
# Tag and push to ACR, then deploy to ACA alongside the parser
```

### 4. Validate

```bash
cd <repo-root>
./deploy/foundry_test-end-to-end.sh
```

---

## Comparison with the Python Orchestrator

| Aspect | Python Orchestrator | Java Orchestrator |
|---|---|---|
| Language | Python 3.10+ | Java 21+ |
| Framework | OpenAI Python SDK | Spring Boot + LangChain4j |
| LLM API | OpenAI Responses API | LangChain4j AiService + @Tool |
| HTTP client | httpx (async) | Spring RestClient (sync) |
| Config | dataclass + dotenv | @ConfigurationProperties + application.yml |
| Telemetry | opentelemetry-python | opentelemetry-java |
| Parser lifecycle | Managed by run_demo.py | Started separately |
| Entry point | `python run_demo.py` | `mvn spring-boot:run -Dspring-boot.run.profiles=demo` |
| Output format | Identical | Identical |

---

## Project Structure

```
javaorchestrator/
├── pom.xml                          # Maven build
├── Dockerfile                       # Multi-stage container build
├── .dockerignore
├── README.md
└── src/
    ├── main/
    │   ├── java/com/microsoft/nvidia/orchestrator/
    │   │   ├── OrchestratorApplication.java     # Spring Boot main + .env loader
    │   │   ├── config/
    │   │   │   └── OrchestratorConfig.java      # @ConfigurationProperties
    │   │   ├── model/                           # Java records for JSON contract
    │   │   │   ├── ParseRequest.java
    │   │   │   ├── ParseResponse.java
    │   │   │   ├── Invoice.java
    │   │   │   ├── LineItem.java
    │   │   │   ├── BoundingBox.java
    │   │   │   ├── Warning.java
    │   │   │   └── DemoResult.java
    │   │   ├── client/
    │   │   │   └── ParserClient.java            # HTTP client for POST /parse
    │   │   ├── agent/
    │   │   │   ├── InvoiceParsingTools.java      # @Tool annotated methods
    │   │   │   ├── InvoiceParsingAgent.java      # LangChain4j AiService
    │   │   │   └── AgentConfiguration.java       # LLM + AiService wiring
    │   │   ├── service/
    │   │   │   └── OrchestratorService.java      # Direct + Agent mode logic
    │   │   ├── telemetry/
    │   │   │   └── TelemetryConfig.java          # OpenTelemetry setup
    │   │   ├── audit/
    │   │   │   └── AuditLogger.java              # Structured JSON audit logs
    │   │   └── demo/
    │   │       └── DemoRunner.java               # CommandLineRunner demo output
    │   └── resources/
    │       ├── application.yml
    │       └── application-demo.yml
    └── test/
        └── java/com/microsoft/nvidia/orchestrator/
            ├── OrchestratorApplicationTests.java
            ├── client/ParserClientTest.java
            ├── agent/InvoiceParsingToolsTest.java
            └── service/OrchestratorServiceTest.java
```
