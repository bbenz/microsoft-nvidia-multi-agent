"""OpenTelemetry setup for the parser service."""

from __future__ import annotations

import logging
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.propagate import set_global_textmap
from opentelemetry.propagators.composite import CompositePropagator
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

from parser_service.config import config

logger = logging.getLogger(__name__)

_tracer: trace.Tracer | None = None


def init_telemetry() -> trace.Tracer:
    """Initialize OpenTelemetry tracing for the parser service."""
    global _tracer
    if _tracer is not None:
        return _tracer

    resource = Resource.create({"service.name": "parser-service"})
    provider = TracerProvider(resource=resource)

    # OTLP exporter if configured
    if config.otel_endpoint:
        try:
            from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import (
                OTLPSpanExporter,
            )

            otlp_exporter = OTLPSpanExporter(endpoint=config.otel_endpoint)
            provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
            logger.info("OTLP exporter configured: %s", config.otel_endpoint)
        except Exception:
            logger.warning("OTLP exporter unavailable, falling back to console")
            provider.add_span_processor(BatchSpanProcessor(ConsoleSpanExporter()))
    else:
        # Silent console exporter — only logs when LOG_LEVEL=DEBUG
        if config.log_level.upper() == "DEBUG":
            provider.add_span_processor(BatchSpanProcessor(ConsoleSpanExporter()))

    trace.set_tracer_provider(provider)

    # W3C trace-context propagation
    set_global_textmap(CompositePropagator([TraceContextTextMapPropagator()]))

    _tracer = trace.get_tracer("parser-service")
    return _tracer


def get_tracer() -> trace.Tracer:
    """Return the configured tracer (initializes on first call)."""
    global _tracer
    if _tracer is None:
        return init_telemetry()
    return _tracer
