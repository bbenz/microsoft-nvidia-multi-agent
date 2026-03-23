package com.microsoft.nvidia.orchestrator.model;

import com.fasterxml.jackson.annotation.JsonProperty;

public record ParseRequest(
        @JsonProperty("pdf_url") String pdfUrl
) {}
