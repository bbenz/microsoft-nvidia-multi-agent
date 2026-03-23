You are a senior engineer building a Java-based orchestrator that replaces the existing Python orchestrator in a Microsoft + NVIDIA hybrid multi-agent demo.

Your output MUST be production-grade, runnable, deterministic for live demos, and optimized for conference presentations.

If anything is ambiguous, make reasonable assumptions and clearly state them — but do NOT ask clarifying questions unless absolutely required for execution.

========================================================
GOAL
========================================================

Build a Java orchestrator that is a drop-in replacement for the existing Python orchestrator (in the `orchestrator/` directory). The Java version lives in a NEW directory called `javaorchestrator/` at the repo root. It communicates with the EXISTING Python parser service (`parser_service/`) — that service is NOT being rewritten or modified in any way.

The Java orchestrator must:

1. Be a Spring Boot 3.x application (Java 21+)
2. Use LangChain4j for LLM integration (tool calling, chat models)
3. Call the existing Python parser service's `POST /parse` endpoint
4. Support the same two execution modes as the Python orchestrator:
   - **Direct mode**: Call the parser directly — deterministic, no LLM dependency
   - **Agent mode**: Use LangChain4j with OpenAI to orchestrate via tool-use
5. Produce the EXACT same output contract / behavior as the Python orchestrator
6. Implement identical OpenTelemetry tracing, audit logging, and correlation ID propagation
7. Be deployable to **Microsoft Azure AI Foundry Agent Service** — the LangChain4j OpenAI client must support a configurable `baseUrl` (`OPENAI_API_BASE`) so it works with both standard OpenAI and Azure AI Foundry-managed GPT-4o endpoints

DO NOT modify any existing files in the repository. The Python orchestrator, parser_service, sample_data, run_demo.py, and all other existing code must remain untouched.

========================================================
CONTEXT: EXISTING PYTHON PARSER SERVICE
========================================================

The Java orchestrator calls the existing Python parser service. Here is its contract:

### POST /parse
Headers:
  - `X-API-Key`: required (validated by parser)
  - `X-Request-Id`: optional correlation ID (orchestrator should always send one)
  - `traceparent`: W3C trace context propagation

Request body:
```json
{ "pdf_url": "https://..." }
```

Response (200 OK):
```json
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
        "bbox": { "x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0, "page": 1 }
      }
    ]
  },
  "warnings": [
    { "code": "...", "message": "...", "details": {} }
  ],
  "summary": "human readable summary"
}
```

### GET /health
Response: `{ "status": "ok", "mock_mode": true|false }`

The parser service runs on `http://localhost:8001` by default and is started separately (e.g., via uvicorn).

========================================================
LANGUAGE + STACK (LOCKED)
========================================================

- Language: Java 21+
- Build tool: Maven (pom.xml) — NOT Gradle
- Framework: Spring Boot 3.x (latest stable)
- LLM Integration: LangChain4j 1.12.2 (pin this version)
  - Use `langchain4j-open-ai` and `langchain4j-open-ai-spring-boot-starter` for OpenAI integration
  - Do NOT use `langchain4j-azure-open-ai` — we use the OpenAI SDK only
  - Use LangChain4j's `@Tool` annotation for tool definitions
  - Use `AiService` pattern for the agent
- HTTP Client: Spring WebClient (reactive) or RestClient (blocking) — your choice, but be consistent
- Telemetry: OpenTelemetry Java SDK + OTLP exporter
- JSON: Jackson (included with Spring Boot)
- Configuration: Spring Boot `application.yml` + environment variable overrides
- Logging: SLF4J + Logback (Spring Boot default)
- Testing: JUnit 5 + Spring Boot Test

========================================================
DIRECTORY STRUCTURE (REQUIRED)
========================================================

```
javaorchestrator/
├── pom.xml
├── README.md
├── Dockerfile
├── .dockerignore
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/
│   │   │       └── microsoft/
│   │   │           └── nvidia/
│   │   │               └── orchestrator/
│   │   │                   ├── OrchestratorApplication.java      # Spring Boot main
│   │   │                   ├── config/
│   │   │                   │   └── OrchestratorConfig.java        # @ConfigurationProperties
│   │   │                   ├── model/
│   │   │                   │   ├── ParseRequest.java
│   │   │                   │   ├── ParseResponse.java
│   │   │                   │   ├── Invoice.java
│   │   │                   │   ├── LineItem.java
│   │   │                   │   ├── BoundingBox.java
│   │   │                   │   ├── Warning.java
│   │   │                   │   └── DemoResult.java               # Wrapper for demo output
│   │   │                   ├── client/
│   │   │                   │   └── ParserClient.java             # HTTP client for POST /parse
│   │   │                   ├── agent/
│   │   │                   │   ├── InvoiceParsingTools.java      # @Tool annotated methods
│   │   │                   │   ├── InvoiceParsingAgent.java      # LangChain4j AiService interface
│   │   │                   │   └── AgentConfiguration.java       # Bean config for AiService
│   │   │                   ├── service/
│   │   │                   │   └── OrchestratorService.java      # Direct + Agent mode logic
│   │   │                   ├── telemetry/
│   │   │                   │   └── TelemetryConfig.java          # OTel setup, tracer beans
│   │   │                   ├── audit/
│   │   │                   │   └── AuditLogger.java              # Structured audit logging
│   │   │                   └── demo/
│   │   │                       └── DemoRunner.java               # CommandLineRunner for demo execution
│   │   └── resources/
│   │       ├── application.yml
│   │       └── application-demo.yml                              # Demo profile overrides
│   └── test/
│       └── java/
│           └── com/
│               └── microsoft/
│                   └── nvidia/
│                       └── orchestrator/
│                           ├── OrchestratorApplicationTests.java
│                           ├── client/
│                           │   └── ParserClientTest.java
│                           ├── agent/
│                           │   └── InvoiceParsingToolsTest.java
│                           └── service/
│                               └── OrchestratorServiceTest.java
```

========================================================
CONFIGURATION (application.yml)
========================================================

```yaml
orchestrator:
  openai:
    api-key: ${OPENAI_API_KEY:}
    model: ${OPENAI_MODEL:gpt-4o}
    api-base: ${OPENAI_API_BASE:}                # OpenAI-compatible endpoint
  parser:
    url: ${PARSER_URL:http://localhost:8001}
    api-key: ${PARSER_API_KEY:demo-api-key-change-me}
    timeout-seconds: ${PARSER_TIMEOUT:120}
  otel:
    endpoint: ${OTEL_EXPORTER_OTLP_ENDPOINT:}
  demo:
    pdf-url: ${DEMO_PDF_URL:http://localhost:8000/sample_invoice_anomaly.pdf}
    mode: ${DEMO_MODE:direct}                    # "direct" or "agent"

logging:
  level:
    com.microsoft.nvidia.orchestrator: ${LOG_LEVEL:INFO}
```

These must all be overridable via environment variables, using the SAME env var names as the Python version for compatibility. The Java orchestrator reads from the same `.env` file at the repo root.

Reference: the repo's `.env.example` contains:
```
OPENAI_API_KEY=sk-your-key-here
OPENAI_MODEL=gpt-4o
OPENAI_API_BASE=https://swedencentral.api.cognitive.microsoft.com/
PARSER_URL=http://localhost:8001
PARSER_API_KEY=demo-api-key-change-me
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
LOG_LEVEL=INFO
DEMO_PDF_URL=http://localhost:8000/sample_invoice_anomaly.pdf
```

The Java app should load the `.env` file from the parent directory (repo root) using `dotenv-java` or Spring's environment abstraction.

========================================================
LANGCHAIN4J AGENT IMPLEMENTATION
========================================================

### Tool Definition (InvoiceParsingTools.java)

Use LangChain4j's `@Tool` annotation:

```java
@Tool("Parse an invoice PDF and extract line items, totals, and detect anomalies")
public String parseInvoice(@P("Public URL of the invoice PDF to parse") String pdfUrl) {
    // Calls ParserClient to POST /parse
    // Returns JSON string of ParseResponse
}
```

### AiService Interface (InvoiceParsingAgent.java)

```java
public interface InvoiceParsingAgent {
    @SystemMessage("You are an invoice analysis agent. When given a PDF URL, use the parse_invoice tool to extract and analyze the invoice.")
    String analyze(@UserMessage String userMessage);
}
```

### Agent Configuration (AgentConfiguration.java)

Wire up the LangChain4j AiService with:
- OpenAI chat model (configured via `OPENAI_API_KEY`, `OPENAI_MODEL`, and optionally `OPENAI_API_BASE`)
- Do NOT use Azure OpenAI client — use the standard OpenAI client only
- The InvoiceParsingTools as tool provider
- Chat memory (simple in-memory, single-turn is fine)

========================================================
EXECUTION MODES
========================================================

The Java orchestrator supports two execution modes, and BOTH modes must work with the parser running either locally or remotely (on ACA). The parser location is controlled solely by the `PARSER_URL` env var.

### Direct Mode (default)
- No LLM dependency
- Call `ParserClient.parse(pdfUrl)` directly
- Return `DemoResult` with parser response data
- Deterministic — suitable for keynote demos
- Works with local parser (`PARSER_URL=http://localhost:8001`) or remote parser on ACA (`PARSER_URL=https://gpu-parse-agent.<env>.azurecontainerapps.io`)

### Agent Mode (requires OPENAI_API_KEY)
- Construct user message: "Here's a PDF URL: {url}\nExtract the line items into JSON and tell me if anything looks off."
- Send to LangChain4j `InvoiceParsingAgent.analyze()` using the OpenAI chat model
- LangChain4j handles the tool call loop automatically
- Extract structured parser response + LLM summary
- Return `DemoResult` with parser response + agent summary
- Works with local or Foundry-deployed OpenAI (controlled by `OPENAI_API_BASE`)
- Works with local or ACA-deployed parser (controlled by `PARSER_URL`)

========================================================
DEPLOYMENT TOPOLOGIES (MUST SUPPORT ALL)
========================================================

The Java orchestrator must work in ALL of these configurations by simply changing env vars. No code changes required.

### Topology 1: Fully Local
- Java orchestrator runs on developer machine
- Parser runs locally: `PARSER_URL=http://localhost:8001`
- OpenAI API direct: `OPENAI_API_KEY=sk-...` (no `OPENAI_API_BASE` needed)
- Sample PDFs served locally: `DEMO_PDF_URL=http://localhost:8000/sample_invoice_anomaly.pdf`

### Topology 2: Local Orchestrator + Remote Parser (ACA)
- Java orchestrator runs on developer machine
- Parser runs on ACA: `PARSER_URL=https://gpu-parse-agent.<env>.azurecontainerapps.io`
- OpenAI API direct or via Foundry
- PDFs can be any public URL

### Topology 3: Fully Cloud (Foundry + ACA)
- Java orchestrator deployed as container to ACA (via Dockerfile)
- Parser runs on ACA with GPU: `PARSER_URL=https://gpu-parse-agent.<env>.azurecontainerapps.io`
- OpenAI via Foundry: `OPENAI_API_BASE=https://<resource>.openai.azure.com/`
- All communication over HTTPS

The `ParserClient` must handle both HTTP and HTTPS URLs in `PARSER_URL`. The `PARSER_API_KEY` header is always sent regardless of topology.

========================================================
PARSER CLIENT
========================================================

`ParserClient` must:
1. Send `POST /parse` with JSON body `{ "pdf_url": "..." }`
2. Include headers:
   - `X-API-Key`: from config
   - `X-Request-Id`: generated UUID
   - `Content-Type: application/json`
   - `traceparent`: W3C trace context (injected via OpenTelemetry)
3. Deserialize response into `ParseResponse` Java record/class
4. Handle errors gracefully (timeout, connection refused, 4xx/5xx)
5. Use configurable timeout (default 120s)

========================================================
OPENTELEMETRY (MANDATORY)
========================================================

Implement end-to-end OpenTelemetry tracing:

Required spans:
- `orchestrator.handle_request` — wraps the entire request
- `orchestrator.call_parser` — wraps the HTTP call to the parser

Trace propagation:
- Inject W3C `traceparent` header into outgoing requests to the parser
- Use OpenTelemetry Java SDK's `W3CTraceContextPropagator`

Configuration:
- If `OTEL_EXPORTER_OTLP_ENDPOINT` is set, use OTLP gRPC exporter
- Otherwise, fall back to logging exporter (non-blocking)
- NEVER let OTel failures crash the application

Use Spring Boot's OpenTelemetry auto-configuration where possible, or configure manually via `@Bean` definitions.

========================================================
AUDIT LOGGING (MANDATORY)
========================================================

Structured JSON audit logs via SLF4J:

Orchestrator events:
- `tool_call`: logged before calling the parser (includes request_id, tool_name, pdf_url — never raw PDF bytes)
- `tool_result`: logged after parser returns (includes request_id, tool_name, success, warning_count, trace_id)

Format:
```json
{
  "timestamp": "2025-...",
  "service": "orchestrator-java",
  "event": "tool_call",
  "request_id": "...",
  "tool_name": "parse_invoice",
  "arguments": { "pdf_url": "..." }
}
```

Never log raw PDF content. Metadata only.

========================================================
DEMO RUNNER
========================================================

`DemoRunner` implements Spring Boot's `CommandLineRunner`.

When the application starts (with `--spring.profiles.active=demo` or a `--demo` flag), it:
1. Calls `OrchestratorService` in the configured mode (direct or agent)
2. Prints the EXACT console output format (see below)
3. Exits after printing

Provide a convenience run script or document the command:
```bash
cd javaorchestrator
mvn spring-boot:run -Dspring-boot.run.profiles=demo
```

Or:
```bash
cd javaorchestrator
mvn package -DskipTests
java -jar target/orchestrator-*.jar --spring.profiles.active=demo
```

========================================================
CONSOLE OUTPUT FORMAT (LOCK THIS EXACTLY)
========================================================

The Java orchestrator demo output MUST match this format exactly (same as the Python version):

```
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
```

This output format MUST be identical to the Python version for consistency in demos.

========================================================
COMPATIBILITY REQUIREMENTS
========================================================

The Java orchestrator MUST be fully compatible with the existing Python parser service, whether the parser is running locally or deployed to ACA:

1. Same environment variables — reuse the same `.env` file
2. Same `POST /parse` request format
3. Same header propagation (X-API-Key, X-Request-Id, traceparent)
4. Same response deserialization (match `ParseResponse` schema exactly)
5. `PARSER_URL` controls where the parser is — local (`http://localhost:8001`) or remote (`https://...azurecontainerapps.io`)
6. Parser service is started separately — the Java orchestrator does NOT manage the parser lifecycle

### Local Demo (parser running locally)
- Terminal 1: Start the parser service (Python): `cd <repo-root> && uvicorn parser_service.main:app --port 8001`
- Terminal 2: Serve sample PDFs: `cd <repo-root> && python -m http.server 8000 -d sample_data`
- Terminal 3: Run the Java orchestrator: `cd javaorchestrator && mvn spring-boot:run -Dspring-boot.run.profiles=demo`

### Cloud Demo (parser on ACA, orchestrator local or on ACA)
- Parser is already deployed to ACA via `deploy/aca_deploy.sh`
- Set `PARSER_URL=https://gpu-parse-agent.<env>.azurecontainerapps.io` in `.env`
- Set `OPENAI_API_BASE` to the Foundry endpoint (configured by `deploy/foundry_deploy.sh`)
- Run: `cd javaorchestrator && mvn spring-boot:run -Dspring-boot.run.profiles=demo -Dspring-boot.run.arguments="--orchestrator.demo.mode=agent"`

The README and demo documentation MUST include step-by-step instructions for BOTH local and cloud workflows, including what output to expect.

========================================================
MAVEN DEPENDENCIES (REQUIRED)
========================================================

The `pom.xml` must include at minimum:
- `spring-boot-starter-web`
- `spring-boot-starter-webflux` (if using WebClient)
- `spring-boot-starter-actuator`
- `spring-boot-starter-test`
- `langchain4j-spring-boot-starter` version **1.12.2**
- `langchain4j-open-ai-spring-boot-starter` version **1.12.2** (OpenAI only — do NOT include azure variant)
- `jackson-databind` (transitive via Spring, but ensure present)
- `opentelemetry-sdk`
- `opentelemetry-exporter-otlp`
- `opentelemetry-api`
- `io.opentelemetry.instrumentation:opentelemetry-spring-boot-starter` (auto-instrumentation)
- `dotenv-java` (for loading the repo root `.env` file)

Use Spring Boot 3.4.x BOM and Java 21 source/target.

Pin LangChain4j version to **1.12.2** using a `<langchain4j.version>` property in the POM.
Reference: https://github.com/langchain4j/langchain4j/releases/tag/1.12.2

========================================================
JAVA RECORDS vs CLASSES
========================================================

Prefer Java records for immutable data objects (ParseRequest, ParseResponse, Invoice, LineItem, BoundingBox, Warning, DemoResult) since we target Java 21+. Use Jackson annotations as needed for JSON deserialization (`@JsonProperty`, `@JsonIgnoreProperties(ignoreUnknown = true)`).

========================================================
ERROR HANDLING
========================================================

- Parser unreachable: Log error, throw descriptive exception, exit demo with clear message
- LLM unreachable (agent mode): Log error, suggest using direct mode
- Invalid API key: Parser returns 401 — surface clearly
- Timeout: Configurable, default 120s, log and fail gracefully
- OTel failures: NEVER crash — log warning and continue

========================================================
TESTING
========================================================

Provide basic tests:
1. `OrchestratorApplicationTests` — Spring context loads
2. `ParserClientTest` — Mock HTTP responses, verify request format
3. `InvoiceParsingToolsTest` — Verify tool method calls ParserClient correctly
4. `OrchestratorServiceTest` — Direct mode returns expected DemoResult

Use `@SpringBootTest` with `MockWebServer` or `WireMock` for HTTP mocking where appropriate.

========================================================
DOCUMENTATION
========================================================

`javaorchestrator/README.md` must include:

1. Prerequisites (Java 21+, Maven 3.9+, Docker optional)
2. Quick start (build + run)
3. Configuration (env vars table — clearly show which vars control local vs cloud)
4. Running locally with the Python parser service (step-by-step multi-terminal instructions)
5. Running against parser on ACA + OpenAI via Foundry (cloud workflow)
6. Direct mode vs Agent mode
7. Docker build and run
8. Deploying to Microsoft Azure AI Foundry Agent Service
9. Deployment topologies table (local, hybrid, fully cloud)
10. Architecture diagram (ASCII)
11. Comparison with the Python orchestrator

========================================================
WHAT NOT TO DO
========================================================

- Do NOT modify any existing Python code
- Do NOT rewrite the parser service in Java
- Do NOT create a new parser service
- Do NOT add Java code outside the `javaorchestrator/` directory
- Do NOT change run_demo.py
- Do NOT change the .env.example (the Java app reads the same env vars)
- Do NOT use deprecated LangChain4j APIs
- Do NOT use `langchain4j-azure-open-ai` — OpenAI SDK only
- Do NOT use Java 8 patterns (var, records, switch expressions, text blocks are all fine)
- Do NOT add unnecessary abstractions — keep it demo-simple

========================================================
MICROSOFT AZURE AI FOUNDRY AGENT SERVICE (MANDATORY)
========================================================

The Java orchestrator MUST be deployable to Microsoft Azure AI Foundry Agent Service, just like the Python orchestrator. The existing repo deploys to Foundry via `deploy/foundry_deploy.sh` (creates an AI Foundry Hub, Project, and GPT-4o deployment). See `docs/deploying_models_foundry.md` for the full guide.

The Java orchestrator must support this deployment model:

### Design for Foundry Compatibility

1. The orchestrator uses the OpenAI-compatible SDK via LangChain4j — Azure AI Foundry exposes GPT-4o through an OpenAI-compatible endpoint (`https://<resource>.openai.azure.com/`), so LangChain4j's OpenAI client works directly.

2. Configuration for Foundry deployment uses the same env vars:
   - `OPENAI_API_KEY` — the Azure OpenAI key from the Foundry-provisioned resource
   - `OPENAI_API_BASE` — the Azure OpenAI endpoint URL
   - `OPENAI_MODEL` — the deployment name (e.g., `gpt-4o`)

3. The LangChain4j OpenAI client must support setting a custom `baseUrl` (via `OPENAI_API_BASE`) so it can point to either:
   - Standard OpenAI (`https://api.openai.com/v1`)
   - Azure AI Foundry endpoint (`https://<resource>.openai.azure.com/`)

4. The `OrchestratorConfig` must expose `openai.api-base` so that when deployed via Foundry, the agent connects to the Foundry-managed GPT-4o deployment.

### Foundry Deployment Documentation

Provide a section in `javaorchestrator/README.md` titled "Deploying to Azure AI Foundry" that documents:

1. How to use the existing `deploy/foundry_deploy.sh` to provision the Azure AI resources (Hub, Project, GPT-4o deployment)
2. How the script writes `OPENAI_API_KEY`, `OPENAI_API_BASE`, and `OPENAI_MODEL` to `.env`
3. How to run the Java orchestrator against the Foundry-deployed model:
   ```bash
   # After running deploy/foundry_deploy.sh, the .env is configured
   cd javaorchestrator
   mvn spring-boot:run -Dspring-boot.run.profiles=demo -Dspring-boot.run.arguments="--orchestrator.demo.mode=agent"
   ```
4. How to deploy the Java orchestrator container to ACA alongside the parser service for a fully cloud-hosted demo
5. Note that the same `deploy/foundry_test-end-to-end.sh` script can validate the deployment (it tests the parser and OpenAI connectivity)

### Agent Configuration for Foundry

In `AgentConfiguration.java`, when building the LangChain4j OpenAI chat model:
- If `OPENAI_API_BASE` is set, use it as the `baseUrl` for the OpenAI client
- If `OPENAI_API_BASE` is empty, default to standard OpenAI API
- This ensures the same code works for both local OpenAI and Foundry-deployed Azure OpenAI

Example pattern:
```java
var builder = OpenAiChatModel.builder()
    .apiKey(config.getOpenai().getApiKey())
    .modelName(config.getOpenai().getModel());

if (config.getOpenai().getApiBase() != null && !config.getOpenai().getApiBase().isBlank()) {
    builder.baseUrl(config.getOpenai().getApiBase());
}

return builder.build();
```

========================================================
DOCKERFILE (REQUIRED)
========================================================

Provide a `javaorchestrator/Dockerfile` for containerizing the Java orchestrator:

- Multi-stage build: Maven build stage + slim JRE runtime stage
- Base image: `eclipse-temurin:21-jdk` for build, `eclipse-temurin:21-jre` for runtime
- Copy only the fat JAR to the runtime stage
- Expose no port (CLI app), but document how to add one if a REST API is added later
- Support env var injection at runtime
- Include a `.dockerignore` in `javaorchestrator/`

Also provide build and run instructions:
```bash
cd javaorchestrator
docker build -t java-orchestrator .
docker run --env-file ../.env --network host java-orchestrator
```

========================================================
DELIVERY FORMAT
========================================================

You must output:

1. Assumptions made
2. Implementation plan
3. Full file tree for `javaorchestrator/`
4. ALL code files with complete implementations (no placeholders, no TODOs)
5. `javaorchestrator/README.md`
6. `javaorchestrator/Dockerfile` and `javaorchestrator/.dockerignore`
7. Maven build + run instructions
8. Docker build + run instructions
9. Sample console output showing the demo

Everything must compile and run with `mvn spring-boot:run`.

Do NOT summarize or skip files.
Generate the full implementation.
