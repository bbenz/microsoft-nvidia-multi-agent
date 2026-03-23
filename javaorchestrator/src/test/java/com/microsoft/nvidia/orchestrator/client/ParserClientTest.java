package com.microsoft.nvidia.orchestrator.client;

import com.microsoft.nvidia.orchestrator.audit.AuditLogger;
import com.microsoft.nvidia.orchestrator.config.OrchestratorConfig;
import com.microsoft.nvidia.orchestrator.model.ParseResponse;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.trace.Tracer;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;

import static org.junit.jupiter.api.Assertions.*;

class ParserClientTest {

    private MockWebServer mockServer;
    private ParserClient parserClient;

    private static final String MOCK_RESPONSE = """
            {
              "request_id": "test-req-id",
              "trace_id": "test-trace-id",
              "invoice": {
                "vendor": "Alpine Office Supplies",
                "invoice_date": "2025-01-15",
                "invoice_number": "INV-1042",
                "currency": "USD",
                "subtotal": 412.00,
                "tax": 32.96,
                "total": 444.96,
                "line_items": [
                  {
                    "description": "A4 Paper",
                    "quantity": 10,
                    "unit_price": 12.00,
                    "amount": 120.00,
                    "bbox": {"x": 0.1, "y": 0.2, "w": 0.8, "h": 0.05, "page": 1}
                  }
                ]
              },
              "warnings": [
                {"code": "SUBTOTAL_MISMATCH", "message": "Subtotal mismatch", "details": {}}
              ],
              "summary": "Test summary"
            }
            """;

    @BeforeEach
    void setUp() throws IOException {
        mockServer = new MockWebServer();
        mockServer.start();

        var config = new OrchestratorConfig();
        config.getParser().setUrl("http://localhost:" + mockServer.getPort());
        config.getParser().setApiKey("test-key");

        var otel = OpenTelemetry.noop();
        var tracer = otel.getTracer("test");
        var auditLogger = new AuditLogger();

        parserClient = new ParserClient(config, tracer, otel, auditLogger);
    }

    @AfterEach
    void tearDown() throws IOException {
        mockServer.shutdown();
    }

    @Test
    void parseReturnsDeserializedResponse() {
        mockServer.enqueue(new MockResponse()
                .setBody(MOCK_RESPONSE)
                .addHeader("Content-Type", "application/json"));

        ParseResponse response = parserClient.parse("http://example.com/test.pdf", "req-123");

        assertNotNull(response);
        assertEquals("test-req-id", response.requestId());
        assertEquals("Alpine Office Supplies", response.invoice().vendor());
        assertEquals("INV-1042", response.invoice().invoiceNumber());
        assertEquals(412.00, response.invoice().subtotal(), 0.01);
        assertEquals(1, response.warnings().size());
        assertEquals("SUBTOTAL_MISMATCH", response.warnings().getFirst().code());
    }

    @Test
    void parseSendsCorrectHeaders() throws InterruptedException {
        mockServer.enqueue(new MockResponse()
                .setBody(MOCK_RESPONSE)
                .addHeader("Content-Type", "application/json"));

        parserClient.parse("http://example.com/test.pdf", "req-456");

        var request = mockServer.takeRequest();
        assertEquals("POST", request.getMethod());
        assertEquals("/parse", request.getPath());
        assertEquals("test-key", request.getHeader("X-API-Key"));
        assertEquals("req-456", request.getHeader("X-Request-Id"));
        assertEquals("application/json", request.getHeader("Content-Type"));
        assertTrue(request.getBody().readUtf8().contains("http://example.com/test.pdf"));
    }

    @Test
    void parseThrowsOnServerError() {
        mockServer.enqueue(new MockResponse().setResponseCode(500));

        assertThrows(RuntimeException.class, () ->
                parserClient.parse("http://example.com/test.pdf"));
    }
}
