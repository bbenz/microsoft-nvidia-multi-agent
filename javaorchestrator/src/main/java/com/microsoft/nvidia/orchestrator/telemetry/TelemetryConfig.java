package com.microsoft.nvidia.orchestrator.telemetry;

import com.microsoft.nvidia.orchestrator.config.OrchestratorConfig;
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.api.trace.propagation.W3CTraceContextPropagator;
import io.opentelemetry.context.propagation.ContextPropagators;
import io.opentelemetry.exporter.logging.LoggingSpanExporter;
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class TelemetryConfig {

    private static final Logger logger = LoggerFactory.getLogger(TelemetryConfig.class);

    @Bean
    public OpenTelemetry openTelemetry(OrchestratorConfig config) {
        var resource = Resource.getDefault().toBuilder()
                .put("service.name", "orchestrator-java")
                .build();

        var tracerProviderBuilder = SdkTracerProvider.builder().setResource(resource);

        var otelEndpoint = config.getOtel().getEndpoint();
        if (otelEndpoint != null && !otelEndpoint.isBlank()) {
            try {
                var otlpExporter = OtlpGrpcSpanExporter.builder()
                        .setEndpoint(otelEndpoint)
                        .build();
                tracerProviderBuilder.addSpanProcessor(BatchSpanProcessor.builder(otlpExporter).build());
                logger.info("OTLP exporter configured: {}", otelEndpoint);
            } catch (Exception e) {
                logger.warn("OTLP exporter unavailable, falling back to logging exporter: {}", e.getMessage());
                tracerProviderBuilder.addSpanProcessor(BatchSpanProcessor.builder(LoggingSpanExporter.create()).build());
            }
        } else {
            tracerProviderBuilder.addSpanProcessor(BatchSpanProcessor.builder(LoggingSpanExporter.create()).build());
        }

        var sdk = OpenTelemetrySdk.builder()
                .setTracerProvider(tracerProviderBuilder.build())
                .setPropagators(ContextPropagators.create(W3CTraceContextPropagator.getInstance()))
                .build();

        GlobalOpenTelemetry.resetForTest();
        return sdk;
    }

    @Bean
    public Tracer tracer(OpenTelemetry openTelemetry) {
        return openTelemetry.getTracer("orchestrator-java");
    }
}
