package com.microsoft.nvidia.orchestrator.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "orchestrator")
public class OrchestratorConfig {

    private final OpenAiConfig openai = new OpenAiConfig();
    private final ParserConfig parser = new ParserConfig();
    private final OtelConfig otel = new OtelConfig();
    private final DemoConfig demo = new DemoConfig();

    public OpenAiConfig getOpenai() { return openai; }
    public ParserConfig getParser() { return parser; }
    public OtelConfig getOtel() { return otel; }
    public DemoConfig getDemo() { return demo; }

    public static class OpenAiConfig {
        private String apiKey = "";
        private String model = "gpt-4o";
        private String apiBase = "";

        public String getApiKey() { return apiKey; }
        public void setApiKey(String apiKey) { this.apiKey = apiKey; }
        public String getModel() { return model; }
        public void setModel(String model) { this.model = model; }
        public String getApiBase() { return apiBase; }
        public void setApiBase(String apiBase) { this.apiBase = apiBase; }
    }

    public static class ParserConfig {
        private String url = "http://localhost:8001";
        private String apiKey = "demo-api-key-change-me";
        private int timeoutSeconds = 120;

        public String getUrl() { return url; }
        public void setUrl(String url) { this.url = url; }
        public String getApiKey() { return apiKey; }
        public void setApiKey(String apiKey) { this.apiKey = apiKey; }
        public int getTimeoutSeconds() { return timeoutSeconds; }
        public void setTimeoutSeconds(int timeoutSeconds) { this.timeoutSeconds = timeoutSeconds; }
    }

    public static class OtelConfig {
        private String endpoint = "";

        public String getEndpoint() { return endpoint; }
        public void setEndpoint(String endpoint) { this.endpoint = endpoint; }
    }

    public static class DemoConfig {
        private String pdfUrl = "http://localhost:8000/sample_invoice_anomaly.pdf";
        private String mode = "direct";

        public String getPdfUrl() { return pdfUrl; }
        public void setPdfUrl(String pdfUrl) { this.pdfUrl = pdfUrl; }
        public String getMode() { return mode; }
        public void setMode(String mode) { this.mode = mode; }
    }
}
