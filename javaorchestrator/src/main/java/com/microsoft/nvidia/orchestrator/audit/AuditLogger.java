package com.microsoft.nvidia.orchestrator.audit;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

@Component
public class AuditLogger {

    private static final Logger logger = LoggerFactory.getLogger("orchestrator.audit");
    private final ObjectMapper objectMapper = new ObjectMapper();

    private void emit(String event, Map<String, Object> fields) {
        var entry = new LinkedHashMap<String, Object>();
        entry.put("timestamp", Instant.now().toString());
        entry.put("service", "orchestrator-java");
        entry.put("event", event);
        entry.putAll(fields);

        try {
            logger.info(objectMapper.writeValueAsString(entry));
        } catch (JsonProcessingException e) {
            logger.warn("Failed to serialize audit log entry: {}", e.getMessage());
        }
    }

    public void logToolCall(String requestId, String toolName, String pdfUrl) {
        emit("tool_call", Map.of(
                "request_id", requestId,
                "tool_name", toolName,
                "arguments", Map.of("pdf_url", pdfUrl)
        ));
    }

    public void logToolResult(String requestId, String toolName, boolean success, int warningCount, String traceId) {
        emit("tool_result", Map.of(
                "request_id", requestId,
                "tool_name", toolName,
                "success", success,
                "warning_count", warningCount,
                "trace_id", traceId
        ));
    }
}
