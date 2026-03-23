package com.microsoft.nvidia.orchestrator.agent;

import dev.langchain4j.service.SystemMessage;
import dev.langchain4j.service.UserMessage;

public interface InvoiceParsingAgent {

    @SystemMessage("You are an invoice analysis agent. When given a PDF URL, use the parseInvoice tool to extract and analyze the invoice. After receiving the tool result, summarize the findings including any anomalies detected.")
    String analyze(@UserMessage String userMessage);
}
