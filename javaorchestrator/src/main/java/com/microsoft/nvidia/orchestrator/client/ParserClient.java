package com.microsoft.nvidia.orchestrator.client;

import com.microsoft.nvidia.orchestrator.audit.AuditLogger;
import com.microsoft.nvidia.orchestrator.config.OrchestratorConfig;
import com.microsoft.nvidia.orchestrator.model.ParseResponse;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Context;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@Component
public class ParserClient {

    private static final Logger logger = LoggerFactory.getLogger(ParserClient.class);

    private final OrchestratorConfig config;
    private final Tracer tracer;
    private final OpenTelemetry openTelemetry;
    private final AuditLogger auditLogger;
    private final RestTemplate restTemplate = new RestTemplate();

    public ParserClient(OrchestratorConfig config, Tracer tracer, OpenTelemetry openTelemetry, AuditLogger auditLogger) {
        this.config = config;
        this.tracer = tracer;
        this.openTelemetry = openTelemetry;
        this.auditLogger = auditLogger;
    }

    public ParseResponse parse(String pdfUrl) {
        return parse(pdfUrl, UUID.randomUUID().toString());
    }

    public ParseResponse parse(String pdfUrl, String requestId) {
        var span = tracer.spanBuilder("orchestrator.call_parser")
                .setAttribute("pdf.url", pdfUrl)
                .setAttribute("request.id", requestId)
                .startSpan();

        try (var scope = span.makeCurrent()) {
            auditLogger.logToolCall(requestId, "parse_invoice", pdfUrl);

            // Build headers
            var headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("X-API-Key", config.getParser().getApiKey());
            headers.set("X-Request-Id", requestId);

            // Inject W3C traceparent header
            openTelemetry.getPropagators().getTextMapPropagator()
                    .inject(Context.current(), headers, (carrier, key, value) -> {
                        if (carrier != null) carrier.set(key, value);
                    });

            // Build JSON body
            var body = Map.of("pdf_url", pdfUrl);
            var entity = new HttpEntity<>(body, headers);

            var url = config.getParser().getUrl() + "/parse";
            var response = restTemplate.postForObject(url, entity, ParseResponse.class);

            if (response == null) {
                throw new RuntimeException("Parser returned null response");
            }

            auditLogger.logToolResult(
                    requestId,
                    "parse_invoice",
                    true,
                    response.warnings() != null ? response.warnings().size() : 0,
                    response.traceId() != null ? response.traceId() : ""
            );

            span.setAttribute("response.warning_count", response.warnings() != null ? response.warnings().size() : 0);
            return response;

        } catch (Exception e) {
            span.recordException(e);
            logger.error("Parser call failed: {}", e.getMessage());
            throw new RuntimeException("Failed to call parser service at " + config.getParser().getUrl() + ": " + e.getMessage(), e);
        } finally {
            span.end();
        }
    }
}
