package com.microsoft.nvidia.orchestrator.agent;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.microsoft.nvidia.orchestrator.client.ParserClient;
import com.microsoft.nvidia.orchestrator.model.ParseResponse;
import dev.langchain4j.agent.tool.P;
import dev.langchain4j.agent.tool.Tool;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

@Component
public class InvoiceParsingTools {

    private static final Logger logger = LoggerFactory.getLogger(InvoiceParsingTools.class);

    private final ParserClient parserClient;
    private final ObjectMapper objectMapper = new ObjectMapper();

    // Stores the last ParseResponse for extraction after agent completes
    private ParseResponse lastParseResponse;

    public InvoiceParsingTools(ParserClient parserClient) {
        this.parserClient = parserClient;
    }

    @Tool("Parse an invoice PDF and extract line items, totals, and detect anomalies. Returns structured JSON with invoice data and warnings.")
    public String parseInvoice(@P("Public URL of the invoice PDF to parse") String pdfUrl) {
        logger.info("Tool called: parse_invoice with pdfUrl={}", pdfUrl);

        var response = parserClient.parse(pdfUrl);
        lastParseResponse = response;

        try {
            return objectMapper.writeValueAsString(response);
        } catch (JsonProcessingException e) {
            logger.error("Failed to serialize parse response: {}", e.getMessage());
            return "{\"error\": \"Failed to serialize response\"}";
        }
    }

    public ParseResponse getLastParseResponse() {
        return lastParseResponse;
    }

    public void clearLastParseResponse() {
        lastParseResponse = null;
    }
}
