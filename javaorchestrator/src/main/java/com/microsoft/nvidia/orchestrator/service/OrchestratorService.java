package com.microsoft.nvidia.orchestrator.service;

import com.microsoft.nvidia.orchestrator.agent.InvoiceParsingAgent;
import com.microsoft.nvidia.orchestrator.agent.InvoiceParsingTools;
import com.microsoft.nvidia.orchestrator.client.ParserClient;
import com.microsoft.nvidia.orchestrator.model.DemoResult;
import io.opentelemetry.api.trace.Tracer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationContext;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
public class OrchestratorService {

    private static final Logger logger = LoggerFactory.getLogger(OrchestratorService.class);

    private final ParserClient parserClient;
    private final Tracer tracer;
    private final ApplicationContext applicationContext;

    public OrchestratorService(ParserClient parserClient, Tracer tracer, ApplicationContext applicationContext) {
        this.parserClient = parserClient;
        this.tracer = tracer;
        this.applicationContext = applicationContext;
    }

    public DemoResult runDirect(String pdfUrl) {
        var span = tracer.spanBuilder("orchestrator.handle_request")
                .setAttribute("mode", "direct")
                .setAttribute("pdf.url", pdfUrl)
                .startSpan();

        try (var scope = span.makeCurrent()) {
            var requestId = UUID.randomUUID().toString();
            var traceId = span.getSpanContext().getTraceId();

            var response = parserClient.parse(pdfUrl, requestId);

            return new DemoResult(requestId, traceId, response, null);
        } finally {
            span.end();
        }
    }

    public DemoResult runAgent(String pdfUrl) {
        var span = tracer.spanBuilder("orchestrator.handle_request")
                .setAttribute("mode", "agent")
                .setAttribute("pdf.url", pdfUrl)
                .startSpan();

        try (var scope = span.makeCurrent()) {
            var requestId = UUID.randomUUID().toString();
            var traceId = span.getSpanContext().getTraceId();

            // Get the agent bean lazily so it only initializes when agent mode is used
            var agent = applicationContext.getBean(InvoiceParsingAgent.class);
            var tools = applicationContext.getBean(InvoiceParsingTools.class);

            tools.clearLastParseResponse();

            var userMessage = "Here's a PDF URL: " + pdfUrl + "\n"
                    + "Extract the line items into JSON and tell me if anything looks off.";

            var agentSummary = agent.analyze(userMessage);

            var parserResponse = tools.getLastParseResponse();

            return new DemoResult(requestId, traceId, parserResponse, agentSummary);

        } catch (Exception e) {
            logger.error("Agent mode failed: {}. Consider using direct mode instead.", e.getMessage());
            throw new RuntimeException("Agent mode failed: " + e.getMessage(), e);
        } finally {
            span.end();
        }
    }
}
