package com.microsoft.nvidia.orchestrator.demo;

import com.microsoft.nvidia.orchestrator.config.OrchestratorConfig;
import com.microsoft.nvidia.orchestrator.model.DemoResult;
import com.microsoft.nvidia.orchestrator.service.OrchestratorService;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Component
@Profile("demo")
public class DemoRunner implements CommandLineRunner {

    private static final String SEP = "--------------------------------------------------";

    private final OrchestratorService orchestratorService;
    private final OrchestratorConfig config;

    public DemoRunner(OrchestratorService orchestratorService, OrchestratorConfig config) {
        this.orchestratorService = orchestratorService;
        this.config = config;
    }

    @Override
    public void run(String... args) {
        var pdfUrl = config.getDemo().getPdfUrl();
        var mode = config.getDemo().getMode();

        DemoResult result;
        if ("agent".equalsIgnoreCase(mode)) {
            if (config.getOpenai().getApiKey() == null || config.getOpenai().getApiKey().isBlank()) {
                System.err.println("ERROR: OPENAI_API_KEY required for agent mode. Set it in .env or environment.");
                System.exit(1);
            }
            result = orchestratorService.runAgent(pdfUrl);
        } else {
            result = orchestratorService.runDirect(pdfUrl);
        }

        printDemoOutput(pdfUrl, result);
        System.exit(0);
    }

    private void printDemoOutput(String pdfUrl, DemoResult result) {
        var response = result.parserResponse();

        System.out.println();
        System.out.println(SEP);
        System.out.println("\uD83E\uDDFE MULTI-AGENT INVOICE ANALYSIS DEMO");
        System.out.println(SEP);
        System.out.println();
        System.out.println("PDF: " + pdfUrl);
        System.out.println("Request ID: " + result.requestId());
        System.out.println("Trace ID: " + result.traceId());
        System.out.println();
        System.out.println("Calling Parse Specialist Agent...");
        System.out.println("\u2713 Parse complete");
        System.out.println();

        // Extracted totals
        if (response != null && response.invoice() != null) {
            var invoice = response.invoice();
            System.out.println(SEP);
            System.out.println("\uD83D\uDCCA EXTRACTED TOTALS");
            System.out.println(SEP);
            System.out.printf("Vendor: %s%n", invoice.vendor());
            System.out.printf("Invoice: %s%n", invoice.invoiceNumber());
            System.out.printf("Subtotal: $%.2f%n", invoice.subtotal());
            System.out.printf("Tax: $%.2f%n", invoice.tax());
            System.out.printf("Total: $%.2f%n", invoice.total());
            System.out.println();
        }

        // Anomalies
        if (response != null && response.warnings() != null && !response.warnings().isEmpty()) {
            System.out.println(SEP);
            System.out.println("\u26A0\uFE0F ANOMALIES DETECTED");
            System.out.println(SEP);
            var warnings = response.warnings();
            for (int i = 0; i < warnings.size(); i++) {
                System.out.printf("%d. %s%n", i + 1, warnings.get(i).message());
            }
            System.out.println();
        } else {
            System.out.println(SEP);
            System.out.println("\u2705 NO ANOMALIES DETECTED");
            System.out.println(SEP);
            System.out.println();
        }

        // Summary
        System.out.println(SEP);
        System.out.println("\uD83E\uDDE0 AGENT SUMMARY");
        System.out.println(SEP);
        if (result.agentSummary() != null && !result.agentSummary().isBlank()) {
            System.out.println(result.agentSummary());
        } else if (response != null && response.summary() != null) {
            System.out.println(response.summary());
        }
        System.out.println();

        // Observability
        System.out.println(SEP);
        System.out.println("\uD83D\uDD2D OBSERVABILITY");
        System.out.println(SEP);
        System.out.println("Trace exported via OpenTelemetry");
        System.out.println("Use trace_id above in your dashboard to view full agent chain.");
        System.out.println();
        System.out.println("Demo complete.");
        System.out.println(SEP);
    }
}
