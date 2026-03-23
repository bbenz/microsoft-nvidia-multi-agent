package com.microsoft.nvidia.orchestrator.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

@JsonIgnoreProperties(ignoreUnknown = true)
public record LineItem(
        @JsonProperty("description") String description,
        @JsonProperty("quantity") int quantity,
        @JsonProperty("unit_price") double unitPrice,
        @JsonProperty("amount") double amount,
        @JsonProperty("bbox") BoundingBox bbox
) {}
