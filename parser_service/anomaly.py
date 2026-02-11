"""Anomaly detection rules — locked specification.

Rules implemented:
1. subtotal != sum(line_items.amount)
2. unit_price > 5× median unit price
3. missing vendor / date / total
"""

from __future__ import annotations

import statistics
from opentelemetry import trace

from parser_service.models import Invoice, Warning

tracer = trace.get_tracer("parser-service")


def check_anomalies(invoice: Invoice) -> tuple[list[Warning], str]:
    """Run all anomaly checks and return (warnings, human_summary)."""
    with tracer.start_as_current_span("parser.anomaly_checks"):
        warnings: list[Warning] = []

        # ---- Rule 1: subtotal vs line-item sum ----
        line_sum = round(sum(item.amount for item in invoice.line_items), 2)
        if abs(invoice.subtotal - line_sum) > 0.005:
            warnings.append(
                Warning(
                    code="SUBTOTAL_MISMATCH",
                    message=(
                        f"Subtotal mismatch: lines sum to ${line_sum:.2f} "
                        f"but subtotal is ${invoice.subtotal:.2f}"
                    ),
                    details={
                        "expected": line_sum,
                        "stated": invoice.subtotal,
                        "difference": round(invoice.subtotal - line_sum, 2),
                    },
                )
            )

        # ---- Rule 2: unit price outlier (> 5× median) ----
        if len(invoice.line_items) >= 3:
            prices = [item.unit_price for item in invoice.line_items]
            median_price = round(statistics.median(prices), 2)

            for item in invoice.line_items:
                if item.unit_price > 5 * median_price:
                    warnings.append(
                        Warning(
                            code="PRICE_OUTLIER",
                            message=(
                                f'High unit price outlier: "{item.description}" '
                                f"= ${item.unit_price:.0f} vs median ${median_price:.0f}"
                            ),
                            details={
                                "item": item.description,
                                "unit_price": item.unit_price,
                                "median": median_price,
                                "ratio": round(item.unit_price / median_price, 1)
                                if median_price
                                else None,
                            },
                        )
                    )

        # ---- Rule 3: missing required fields ----
        missing = []
        if not invoice.vendor:
            missing.append("vendor")
        if not invoice.invoice_date:
            missing.append("date")
        if invoice.total == 0.0:
            missing.append("total")

        if missing:
            warnings.append(
                Warning(
                    code="MISSING_FIELDS",
                    message=f"Missing required fields: {', '.join(missing)}",
                    details={"fields": missing},
                )
            )

        # ---- Build human summary ----
        summary = _build_summary(invoice, warnings)

        return warnings, summary


def _build_summary(invoice: Invoice, warnings: list[Warning]) -> str:
    """Generate a deterministic human-readable summary."""
    if not warnings:
        return (
            f"The invoice from {invoice.vendor} ({invoice.invoice_number}) "
            f"was parsed successfully. No anomalies were detected."
        )

    anomaly_descriptions = []
    for w in warnings:
        if w.code == "SUBTOTAL_MISMATCH":
            anomaly_descriptions.append(
                "The subtotal does not match the sum of line items."
            )
        elif w.code == "PRICE_OUTLIER":
            anomaly_descriptions.append(
                "One line item has a significantly higher unit price than others."
            )
        elif w.code == "MISSING_FIELDS":
            anomaly_descriptions.append(
                f"Required fields are missing: {w.details.get('fields', [])}."
            )

    count = len(warnings)
    count_word = {1: "One", 2: "Two", 3: "Three"}.get(count, str(count))
    word = "anomaly was" if count == 1 else "anomalies were"

    lines = [f"The invoice was parsed successfully. {count_word} {word} detected:"]
    for desc in anomaly_descriptions:
        lines.append(f"- {desc}")
    lines.append("")
    lines.append("This may indicate a calculation error or incorrect entry.")

    return "\n".join(lines)
