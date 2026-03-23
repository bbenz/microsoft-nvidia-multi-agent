package com.microsoft.nvidia.orchestrator.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

@JsonIgnoreProperties(ignoreUnknown = true)
public record BoundingBox(
        @JsonProperty("x") double x,
        @JsonProperty("y") double y,
        @JsonProperty("w") double w,
        @JsonProperty("h") double h,
        @JsonProperty("page") int page
) {
    public BoundingBox() {
        this(0.0, 0.0, 0.0, 0.0, 1);
    }
}
