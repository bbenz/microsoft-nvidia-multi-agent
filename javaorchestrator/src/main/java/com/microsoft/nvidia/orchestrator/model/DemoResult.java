package com.microsoft.nvidia.orchestrator.model;

public record DemoResult(
        String requestId,
        String traceId,
        ParseResponse parserResponse,
        String agentSummary
) {}
