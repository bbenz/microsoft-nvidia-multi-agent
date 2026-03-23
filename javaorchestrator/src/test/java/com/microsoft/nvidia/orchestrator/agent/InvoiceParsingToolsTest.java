package com.microsoft.nvidia.orchestrator.agent;

import com.microsoft.nvidia.orchestrator.client.ParserClient;
import com.microsoft.nvidia.orchestrator.model.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class InvoiceParsingToolsTest {

    @Mock
    private ParserClient parserClient;

    @InjectMocks
    private InvoiceParsingTools tools;

    @Test
    void parseInvoiceReturnsJsonAndStoresResponse() {
        var invoice = new Invoice("Vendor", "2025-01-01", "INV-1", "USD",
                100.0, 8.0, 108.0,
                List.of(new LineItem("Item", 1, 100.0, 100.0, new BoundingBox())));
        var warning = new Warning("TEST", "Test warning", Map.of());
        var mockResponse = new ParseResponse("req-1", "trace-1", invoice, List.of(warning), "Test summary");

        when(parserClient.parse(anyString())).thenReturn(mockResponse);

        var result = tools.parseInvoice("http://example.com/test.pdf");

        assertNotNull(result);
        assertTrue(result.contains("Vendor"));
        assertTrue(result.contains("INV-1"));
        assertEquals(mockResponse, tools.getLastParseResponse());
    }

    @Test
    void clearLastParseResponseWorks() {
        tools.clearLastParseResponse();
        assertNull(tools.getLastParseResponse());
    }
}
