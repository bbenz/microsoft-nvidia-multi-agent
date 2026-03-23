package com.microsoft.nvidia.orchestrator.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.List;

@JsonIgnoreProperties(ignoreUnknown = true)
public record ParseResponse(
        @JsonProperty("request_id") String requestId,
        @JsonProperty("trace_id") String traceId,
        @JsonProperty("invoice") Invoice invoice,
        @JsonProperty("warnings") List<Warning> warnings,
        @JsonProperty("summary") String summary
) {}
