"""Invoice data normalizer.

Ensures all fields conform to the output contract:
- Currency defaults to USD
- Amounts rounded to 2 decimal places
- Bounding boxes clamped to [0..1]
"""

from __future__ import annotations

from opentelemetry import trace

from parser_service.models import Invoice

tracer = trace.get_tracer("parser-service")


def normalize(invoice: Invoice) -> Invoice:
    """Normalize invoice data in-place and return it."""
    with tracer.start_as_current_span("parser.normalize"):
        if not invoice.currency:
            invoice.currency = "USD"

        invoice.subtotal = round(invoice.subtotal, 2)
        invoice.tax = round(invoice.tax, 2)
        invoice.total = round(invoice.total, 2)

        for item in invoice.line_items:
            item.unit_price = round(item.unit_price, 2)
            item.amount = round(item.amount, 2)

            # Clamp bbox to [0..1]
            bb = item.bbox
            bb.x = max(0.0, min(1.0, bb.x))
            bb.y = max(0.0, min(1.0, bb.y))
            bb.w = max(0.0, min(1.0, bb.w))
            bb.h = max(0.0, min(1.0, bb.h))
            bb.page = max(1, bb.page)

        return invoice
