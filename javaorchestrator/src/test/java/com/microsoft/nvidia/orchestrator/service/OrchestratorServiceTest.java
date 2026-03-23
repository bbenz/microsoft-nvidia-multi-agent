package com.microsoft.nvidia.orchestrator.service;

import com.microsoft.nvidia.orchestrator.client.ParserClient;
import com.microsoft.nvidia.orchestrator.model.*;
import io.opentelemetry.api.OpenTelemetry;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.context.ApplicationContext;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class OrchestratorServiceTest {

    @Mock
    private ParserClient parserClient;

    @Mock
    private ApplicationContext applicationContext;

    @Test
    void runDirectReturnsDemoResult() {
        var invoice = new Invoice("Alpine Office Supplies", "2025-01-15", "INV-1042", "USD",
                412.0, 32.96, 444.96,
                List.of(new LineItem("A4 Paper", 10, 12.0, 120.0, new BoundingBox())));
        var warning = new Warning("SUBTOTAL_MISMATCH", "Subtotal mismatch", Map.of());
        var mockResponse = new ParseResponse("req-1", "trace-1", invoice, List.of(warning), "Summary");

        when(parserClient.parse(anyString(), anyString())).thenReturn(mockResponse);

        var otel = OpenTelemetry.noop();
        var tracer = otel.getTracer("test");
        var service = new OrchestratorService(parserClient, tracer, applicationContext);

        var result = service.runDirect("http://example.com/test.pdf");

        assertNotNull(result);
        assertNotNull(result.requestId());
        assertNotNull(result.traceId());
        assertEquals(mockResponse, result.parserResponse());
        assertNull(result.agentSummary());
        assertEquals("Alpine Office Supplies", result.parserResponse().invoice().vendor());
    }
}
