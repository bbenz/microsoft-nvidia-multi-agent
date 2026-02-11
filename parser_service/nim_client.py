"""NVIDIA Nemotron Parse NIM client with mock fallback.

In mock mode (no NIM_ENDPOINT configured), returns deterministic
sample data matching the generated demo invoices.
"""

from __future__ import annotations

import logging
from typing import Any

import httpx
from opentelemetry import trace

from parser_service.config import config
from parser_service.models import BoundingBox, Invoice, LineItem

logger = logging.getLogger(__name__)
tracer = trace.get_tracer("parser-service")

# ---------------------------------------------------------------------------
# Deterministic mock data — matches sample_data/generate_sample_invoice_pdf.py
# ---------------------------------------------------------------------------

_ANOMALY_INVOICE = Invoice(
    vendor="Alpine Office Supplies",
    invoice_date="2025-11-15",
    invoice_number="INV-1042",
    currency="USD",
    subtotal=412.00,  # Deliberately WRONG — real sum is 392.00
    tax=32.96,
    total=444.96,
    line_items=[
        LineItem(
            description="Copy Paper A4 (Case)",
            quantity=2,
            unit_price=10.00,
            amount=20.00,
            bbox=BoundingBox(x=0.05, y=0.35, w=0.90, h=0.04, page=1),
        ),
        LineItem(
            description="Ink Cartridge Black",
            quantity=1,
            unit_price=35.00,
            amount=35.00,
            bbox=BoundingBox(x=0.05, y=0.40, w=0.90, h=0.04, page=1),
        ),
        LineItem(
            description="Desk Organizer",
            quantity=1,
            unit_price=42.00,
            amount=42.00,
            bbox=BoundingBox(x=0.05, y=0.45, w=0.90, h=0.04, page=1),
        ),
        LineItem(
            description="Wireless Mouse",
            quantity=1,
            unit_price=45.00,
            amount=45.00,
            bbox=BoundingBox(x=0.05, y=0.25, w=0.90, h=0.04, page=2),
        ),
        LineItem(
            description="Premium Support",
            quantity=1,
            unit_price=250.00,
            amount=250.00,
            bbox=BoundingBox(x=0.05, y=0.30, w=0.90, h=0.04, page=2),
        ),
    ],
)

_CLEAN_INVOICE = Invoice(
    vendor="Alpine Office Supplies",
    invoice_date="2025-11-14",
    invoice_number="INV-1041",
    currency="USD",
    subtotal=197.00,
    tax=15.76,
    total=212.76,
    line_items=[
        LineItem(
            description="Copy Paper A4 (Case)",
            quantity=2,
            unit_price=10.00,
            amount=20.00,
            bbox=BoundingBox(x=0.05, y=0.35, w=0.90, h=0.04, page=1),
        ),
        LineItem(
            description="Ink Cartridge Black",
            quantity=1,
            unit_price=35.00,
            amount=35.00,
            bbox=BoundingBox(x=0.05, y=0.40, w=0.90, h=0.04, page=1),
        ),
        LineItem(
            description="Desk Organizer",
            quantity=1,
            unit_price=42.00,
            amount=42.00,
            bbox=BoundingBox(x=0.05, y=0.45, w=0.90, h=0.04, page=1),
        ),
        LineItem(
            description="Wireless Mouse",
            quantity=1,
            unit_price=45.00,
            amount=45.00,
            bbox=BoundingBox(x=0.05, y=0.25, w=0.90, h=0.04, page=2),
        ),
        LineItem(
            description="USB-C Hub",
            quantity=1,
            unit_price=55.00,
            amount=55.00,
            bbox=BoundingBox(x=0.05, y=0.30, w=0.90, h=0.04, page=2),
        ),
    ],
)


def _detect_mock_variant(pdf_url: str) -> Invoice:
    """Choose mock data based on the PDF URL filename."""
    url_lower = pdf_url.lower()
    if "anomaly" in url_lower:
        return _ANOMALY_INVOICE.model_copy(deep=True)
    return _CLEAN_INVOICE.model_copy(deep=True)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


async def fetch_pdf(pdf_url: str) -> bytes:
    """Download PDF bytes from *pdf_url*."""
    with tracer.start_as_current_span("parser.fetch_pdf", attributes={"pdf.url": pdf_url}):
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.get(pdf_url)
            resp.raise_for_status()
            logger.info("Fetched PDF: %d bytes from %s", len(resp.content), pdf_url)
            return resp.content


async def call_nim(pdf_bytes: bytes) -> dict[str, Any]:
    """Call Nemotron Parse NIM and return raw extraction result."""
    with tracer.start_as_current_span("parser.call_nim") as span:
        span.set_attribute("nim.endpoint", config.nim_endpoint)
        span.set_attribute("nim.model_id", config.nim_model_id)
        span.set_attribute("pdf.size_bytes", len(pdf_bytes))

        import base64

        payload = {
            "model": config.nim_model_id,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "pdf",
                            "data": base64.b64encode(pdf_bytes).decode(),
                        }
                    ],
                }
            ],
        }

        headers = {"Content-Type": "application/json"}
        if config.nim_api_key:
            headers["Authorization"] = f"Bearer {config.nim_api_key}"

        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(
                f"{config.nim_endpoint}/v1/chat/completions",
                json=payload,
                headers=headers,
            )
            resp.raise_for_status()
            result = resp.json()
            span.set_attribute("nim.response_length", len(str(result)))
            return result


async def extract_invoice(pdf_url: str) -> Invoice:
    """Extract invoice data from a PDF URL.

    Uses Nemotron Parse NIM when configured, otherwise returns
    deterministic mock data for demo purposes.
    """
    if config.mock_mode:
        logger.info("Mock mode: returning deterministic data for %s", pdf_url)
        with tracer.start_as_current_span("parser.call_nim", attributes={"mock": True}):
            return _detect_mock_variant(pdf_url)

    # Real NIM path
    pdf_bytes = await fetch_pdf(pdf_url)
    raw = await call_nim(pdf_bytes)
    return _parse_nim_response(raw)


def _parse_nim_response(raw: dict[str, Any]) -> Invoice:
    """Convert raw NIM response into our Invoice model.

    This is a best-effort parser for the structured text
    returned by Nemotron Parse. In production you would add
    more robust extraction logic here.
    """
    # NIM returns markdown/text — for now, create a placeholder.
    # A real implementation would parse the structured output.
    content = raw.get("choices", [{}])[0].get("message", {}).get("content", "")
    logger.info("NIM returned %d chars of content", len(content))

    # Fallback to empty invoice — real implementation would parse content
    return Invoice(vendor="(parsed)", invoice_date="(parsed)", invoice_number="(parsed)")
