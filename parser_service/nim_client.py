"""NVIDIA Nemotron Parse NIM client with mock fallback.

In mock mode (no NIM_ENDPOINT configured), returns deterministic
sample data matching the generated demo invoices.
"""

from __future__ import annotations

import base64
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


def _pdf_pages_to_base64(pdf_bytes: bytes) -> list[tuple[str, str]]:
    """Convert PDF pages to base64-encoded PNG images.

    Returns list of (base64_str, mime_type) tuples, one per page.
    """
    import io
    import pypdfium2 as pdfium

    pdf = pdfium.PdfDocument(pdf_bytes)
    pages = []
    for i in range(len(pdf)):
        page = pdf[i]
        # Render at 300 DPI for good OCR quality
        bitmap = page.render(scale=300 / 72)
        pil_image = bitmap.to_pil()
        buf = io.BytesIO()
        pil_image.save(buf, format="PNG")
        b64 = base64.b64encode(buf.getvalue()).decode("ascii")
        pages.append((b64, "image/png"))
    pdf.close()
    return pages


async def _call_nim_single_page(
    b64: str, mime: str, headers: dict[str, str], url: str
) -> dict[str, Any]:
    """Send a single page image to Nemotron Parse and return raw result."""
    img_tag = f'<img src="data:{mime};base64,{b64}" />'
    tool_name = "markdown_no_bbox"
    payload = {
        "model": config.nim_model_id,
        "messages": [{"role": "user", "content": img_tag}],
        "tools": [{"type": "function", "function": {"name": tool_name}}],
        "tool_choice": {"type": "function", "function": {"name": tool_name}},
        "max_tokens": 8192,
    }
    async with httpx.AsyncClient(timeout=120.0) as client:
        resp = await client.post(url, json=payload, headers=headers)
        resp.raise_for_status()
        return resp.json()


async def call_nim(pdf_bytes: bytes) -> dict[str, Any]:
    """Call Nemotron Parse NIM and return raw extraction result.

    The NVIDIA API allows at most 1 image per request, so multi-page
    PDFs are sent page-by-page and the results are merged.
    """
    with tracer.start_as_current_span("parser.call_nim") as span:
        span.set_attribute("nim.endpoint", config.nim_endpoint)
        span.set_attribute("nim.model_id", config.nim_model_id)
        span.set_attribute("pdf.size_bytes", len(pdf_bytes))

        page_images = _pdf_pages_to_base64(pdf_bytes)
        span.set_attribute("pdf.num_pages", len(page_images))
        logger.info("Converted PDF to %d page image(s)", len(page_images))

        headers = {"Content-Type": "application/json"}
        if config.nim_api_key:
            headers["Authorization"] = f"Bearer {config.nim_api_key}"
        url = f"{config.nim_endpoint.rstrip('/')}/chat/completions"

        # Send each page individually (API limit: 1 image per request)
        page_results = []
        for idx, (b64, mime) in enumerate(page_images):
            logger.info("Sending page %d/%d to NIM", idx + 1, len(page_images))
            result = await _call_nim_single_page(b64, mime, headers, url)
            page_results.append(result)

        # Merge: concatenate tool_calls arguments from all pages
        if len(page_results) == 1:
            merged = page_results[0]
        else:
            merged = page_results[0]
            first_msg = merged["choices"][0]["message"]
            tool_calls = first_msg.get("tool_calls", [])
            if tool_calls:
                combined_args = tool_calls[0]["function"]["arguments"]
                for pr in page_results[1:]:
                    tc = pr.get("choices", [{}])[0].get("message", {}).get("tool_calls", [])
                    if tc:
                        combined_args += "\n" + tc[0]["function"]["arguments"]
                tool_calls[0]["function"]["arguments"] = combined_args

        span.set_attribute("nim.response_length", len(str(merged)))
        return merged


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

    Nemotron Parse returns results as tool_calls where the arguments
    field is a JSON string like: [{"text": "...markdown..."}]
    We extract and combine the text from all pages.
    """
    import json as _json
    import re

    message = raw.get("choices", [{}])[0].get("message", {})
    content = ""
    tool_calls = message.get("tool_calls", [])
    if tool_calls:
        args_str = tool_calls[0].get("function", {}).get("arguments", "")
        # arguments is a JSON string: [{"text": "..."}] or concatenated per page
        try:
            # Handle concatenated page results: "[{...}]\n[{...}]"
            parts = []
            for chunk in re.split(r"\]\s*\[", args_str):
                chunk = chunk.strip()
                if not chunk.startswith("["):
                    chunk = "[" + chunk
                if not chunk.endswith("]"):
                    chunk = chunk + "]"
                parsed = _json.loads(chunk)
                for item in parsed:
                    if isinstance(item, dict) and "text" in item:
                        parts.append(item["text"])
            content = "\n".join(parts)
        except (_json.JSONDecodeError, TypeError):
            content = args_str
    if not content:
        content = message.get("content", "")
    logger.info("NIM returned %d chars of content", len(content))

    def _find(pattern: str, text: str, default: str = "") -> str:
        m = re.search(pattern, text, re.IGNORECASE)
        return m.group(1).strip() if m else default

    def _find_amount(pattern: str, text: str) -> float:
        m = re.search(pattern, text, re.IGNORECASE)
        if m:
            val = m.group(1).replace(",", "").replace("$", "")
            try:
                return float(val)
            except ValueError:
                return 0.0
        return 0.0

    # Extract vendor — try markdown heading first, then plain text lines
    # Skip headings that are just "INVOICE" or "Bill To"
    vendor = "(parsed)"
    for m in re.finditer(r"#\s+([A-Z][^\n]+)", content):
        candidate = m.group(1).strip().strip("*")
        if candidate.upper() not in ("INVOICE", "BILL TO:", "BILL TO"):
            vendor = candidate
            break
    # Fallback: look for lines containing "Supplies", "Corp", "Inc", "LLC", "Ltd"
    if vendor == "(parsed)":
        for m in re.finditer(r"^([A-Za-z][^\n]{2,50})$", content, re.MULTILINE):
            candidate = m.group(1).strip()
            upper = candidate.upper()
            if upper in ("INVOICE", "BILL TO:", "BILL TO", "CONTINUED ON NEXT PAGE..."):
                continue
            if any(kw in upper for kw in ("SUPPLIES", "CORP", "INC", "LLC", "LTD", "COMPANY")):
                vendor = candidate
                break
    inv_num = _find(r"(INV-\d+)", content, "(parsed)")
    inv_date = _find(r"(?:^|\n)\s*Date:?\s*(\d{4}[\-/]\d{2}[\-/]\d{2})", content, "(parsed)")
    subtotal = _find_amount(r"Subtotal:?\s*(?:&\s*)*\$?([\d,.]+)", content)
    if subtotal == 0.0:
        subtotal = _find_amount(r"multicolumn\{[^}]*\}\{[^}]*\}\{Subtotal:?\s*\$?([\d,.]+)", content)
    tax = _find_amount(r"Tax\s*\([^)]*\):?\s*(?:&\s*)*\$?([\d,.]+)", content)
    total = _find_amount(r"\bTOTAL:?\s*(?:&\s*)*\$?([\d,.]+)", content)

    # Parse line items — Nemotron uses LaTeX tabular format:
    #   Copy Paper A4 (Case) & 2 & $10.00 & $20.00\\
    line_items = []
    for row in re.finditer(
        r"([A-Za-z][^&\n]+?)\s*&\s*(\d+)\s*&\s*\$?([\d,.]+)\s*&\s*\$?([\d,.]+)",
        content,
    ):
        desc = row.group(1).strip().strip("*")
        # Skip header rows
        if desc.lower() in ("description", "qty", "unit price", "amount"):
            continue
        try:
            line_items.append(
                LineItem(
                    description=desc,
                    quantity=int(row.group(2)),
                    unit_price=float(row.group(3).replace(",", "")),
                    amount=float(row.group(4).replace(",", "")),
                )
            )
        except (ValueError, IndexError):
            continue

    # Also try markdown pipe tables as fallback
    if not line_items:
        for row in re.finditer(
            r"\|\s*(.+?)\s*\|\s*(\d+)\s*\|\s*\$?([\d,.]+)\s*\|\s*\$?([\d,.]+)\s*\|",
            content,
        ):
            desc = row.group(1).strip()
            if desc.lower() in ("description", "---", "") or desc.startswith("--"):
                continue
            try:
                line_items.append(
                    LineItem(
                        description=desc,
                        quantity=int(row.group(2)),
                        unit_price=float(row.group(3).replace(",", "")),
                        amount=float(row.group(4).replace(",", "")),
                    )
                )
            except (ValueError, IndexError):
                continue

    # Compute subtotal/total from line items when NIM omits them
    if subtotal == 0.0 and line_items:
        subtotal = round(sum(li.amount for li in line_items), 2)
        logger.info("Computed subtotal from line items: %.2f", subtotal)
    if total == 0.0 and subtotal > 0:
        total = round(subtotal + tax, 2)
        logger.info("Computed total from subtotal + tax: %.2f", total)

    return Invoice(
        vendor=vendor,
        invoice_date=inv_date,
        invoice_number=inv_num,
        subtotal=subtotal,
        tax=tax,
        total=total,
        line_items=line_items,
    )
