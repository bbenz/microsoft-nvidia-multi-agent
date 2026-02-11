"""Parser Service — FastAPI application.

POST /parse  — Extract invoice data from a PDF URL.
GET  /health — Liveness check.
"""

from __future__ import annotations

import logging
import time
import uuid

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse
from opentelemetry import trace
from opentelemetry.propagate import extract

from parser_service.anomaly import check_anomalies
from parser_service.audit import log_parse_completed, log_request_received
from parser_service.config import config
from parser_service.models import ParseRequest, ParseResponse
from parser_service.nim_client import extract_invoice
from parser_service.normalizer import normalize
from parser_service.telemetry import get_tracer, init_telemetry

# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=getattr(logging, config.log_level.upper(), logging.INFO),
    format="%(asctime)s %(levelname)-8s [%(name)s] %(message)s",
)
logger = logging.getLogger("parser_service")

# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------

app = FastAPI(
    title="GPU Parse Specialist Agent",
    version="0.1.0",
    description="Invoice parsing via NVIDIA Nemotron Parse NIM",
)


@app.on_event("startup")
async def _startup() -> None:
    init_telemetry()
    logger.info(
        "Parser service started — mock_mode=%s, otel=%s",
        config.mock_mode,
        bool(config.otel_endpoint),
    )


# ---------------------------------------------------------------------------
# Auth dependency
# ---------------------------------------------------------------------------


def _verify_api_key(x_api_key: str = Header(default="")) -> None:
    if config.api_key and x_api_key != config.api_key:
        raise HTTPException(status_code=401, detail="Invalid or missing API key")


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.get("/health")
async def health():
    return {"status": "ok", "mock_mode": config.mock_mode}


@app.post("/parse", response_model=ParseResponse)
async def parse_invoice_endpoint(
    body: ParseRequest,
    request: Request,
    x_api_key: str = Header(default=""),
    x_request_id: str = Header(default=""),
):
    """Main parse endpoint — the specialist agent's entry point."""
    _verify_api_key(x_api_key)

    tracer = get_tracer()

    # Propagate W3C trace context from orchestrator
    ctx = extract(carrier=dict(request.headers))

    with tracer.start_as_current_span(
        "parser.handle_parse",
        context=ctx,
        attributes={"pdf.url": body.pdf_url},
    ) as span:
        request_id = x_request_id or str(uuid.uuid4())
        trace_id = format(span.get_span_context().trace_id, "032x")

        span.set_attribute("request.id", request_id)

        log_request_received(request_id, body.pdf_url, trace_id)
        t0 = time.perf_counter()

        # 1. Extract invoice (NIM or mock)
        invoice = await extract_invoice(body.pdf_url)

        # 2. Normalize
        invoice = normalize(invoice)

        # 3. Anomaly checks
        warnings, summary = check_anomalies(invoice)

        duration_ms = (time.perf_counter() - t0) * 1000.0

        log_parse_completed(
            request_id=request_id,
            trace_id=trace_id,
            line_item_count=len(invoice.line_items),
            warning_count=len(warnings),
            duration_ms=duration_ms,
        )

        response = ParseResponse(
            request_id=request_id,
            trace_id=trace_id,
            invoice=invoice,
            warnings=warnings,
            summary=summary,
        )

        span.set_attribute("response.warning_count", len(warnings))
        span.set_attribute("response.line_item_count", len(invoice.line_items))

        return response


# ---------------------------------------------------------------------------
# Error handler
# ---------------------------------------------------------------------------


@app.exception_handler(Exception)
async def _global_error_handler(request: Request, exc: Exception):
    logger.exception("Unhandled error: %s", exc)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error", "error": str(exc)},
    )
