package com.microsoft.nvidia.orchestrator.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.List;

@JsonIgnoreProperties(ignoreUnknown = true)
public record Invoice(
        @JsonProperty("vendor") String vendor,
        @JsonProperty("invoice_date") String invoiceDate,
        @JsonProperty("invoice_number") String invoiceNumber,
        @JsonProperty("currency") String currency,
        @JsonProperty("subtotal") double subtotal,
        @JsonProperty("tax") double tax,
        @JsonProperty("total") double total,
        @JsonProperty("line_items") List<LineItem> lineItems
) {}
