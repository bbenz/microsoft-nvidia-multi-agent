#!/usr/bin/env python3
"""Generate deterministic sample invoice PDFs for the demo.

Outputs:
  sample_data/sample_invoice_clean.pdf     — valid invoice, no anomalies
  sample_data/sample_invoice_anomaly.pdf   — deliberate subtotal mismatch + price outlier

Run:
  python sample_data/generate_sample_invoice_pdf.py
"""

from __future__ import annotations

import os
from pathlib import Path

from fpdf import FPDF

HERE = Path(__file__).resolve().parent


# ============================================================
# Data definitions — deterministic, hardcoded
# ============================================================

VENDOR = "Alpine Office Supplies"
VENDOR_ADDRESS = "123 Mountain View Road, Denver, CO 80202"
VENDOR_PHONE = "(303) 555-0142"

BILL_TO = "Contoso Ltd."
BILL_TO_ADDRESS = "One Microsoft Way, Redmond, WA 98052"

# ---- Clean invoice ----
CLEAN = {
    "invoice_number": "INV-1041",
    "invoice_date": "2025-11-14",
    "due_date": "2025-12-14",
    "line_items": [
        ("Copy Paper A4 (Case)", 2, 10.00),
        ("Ink Cartridge Black", 1, 35.00),
        ("Desk Organizer", 1, 42.00),
        ("Wireless Mouse", 1, 45.00),
        ("USB-C Hub", 1, 55.00),
    ],
    "subtotal": 197.00,  # Correct: 20+35+42+45+55
    "tax_rate": 0.08,
    "tax": 15.76,
    "total": 212.76,
}

# ---- Anomaly invoice ----
ANOMALY = {
    "invoice_number": "INV-1042",
    "invoice_date": "2025-11-15",
    "due_date": "2025-12-15",
    "line_items": [
        ("Copy Paper A4 (Case)", 2, 10.00),
        ("Ink Cartridge Black", 1, 35.00),
        ("Desk Organizer", 1, 42.00),
        ("Wireless Mouse", 1, 45.00),
        ("Premium Support", 1, 250.00),  # Outlier: 250 > 5×42
    ],
    "subtotal": 412.00,  # WRONG — real sum is 392.00
    "tax_rate": 0.08,
    "tax": 32.96,  # 8% of stated subtotal
    "total": 444.96,
}


# ============================================================
# PDF generation
# ============================================================


def _make_invoice_pdf(data: dict, output_path: Path) -> None:
    """Render a multi-page professional invoice PDF."""
    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=20)

    # ---- Page 1: Header + first line items ----
    pdf.add_page()

    # Company header
    pdf.set_font("Helvetica", "B", 22)
    pdf.cell(0, 12, VENDOR, new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 10)
    pdf.cell(0, 5, VENDOR_ADDRESS, new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 5, f"Phone: {VENDOR_PHONE}", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(8)

    # Invoice details
    pdf.set_font("Helvetica", "B", 16)
    pdf.cell(0, 10, "INVOICE", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 11)
    pdf.cell(95, 6, f"Invoice #: {data['invoice_number']}")
    pdf.cell(0, 6, f"Date: {data['invoice_date']}", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(95, 6, f"Due Date: {data['due_date']}")
    pdf.cell(0, 6, "Terms: Net 30", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(6)

    # Bill To
    pdf.set_font("Helvetica", "B", 11)
    pdf.cell(0, 6, "Bill To:", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 11)
    pdf.cell(0, 6, BILL_TO, new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 6, BILL_TO_ADDRESS, new_x="LMARGIN", new_y="NEXT")
    pdf.ln(8)

    # Table header
    pdf.set_fill_color(60, 60, 100)
    pdf.set_text_color(255, 255, 255)
    pdf.set_font("Helvetica", "B", 10)
    pdf.cell(80, 8, "Description", fill=True)
    pdf.cell(25, 8, "Qty", align="C", fill=True)
    pdf.cell(35, 8, "Unit Price", align="R", fill=True)
    pdf.cell(40, 8, "Amount", align="R", fill=True, new_x="LMARGIN", new_y="NEXT")

    # Restore text color
    pdf.set_text_color(0, 0, 0)
    pdf.set_font("Helvetica", "", 10)

    items = data["line_items"]
    # Split: first 3 items on page 1, remaining on page 2
    page1_items = items[:3]
    page2_items = items[3:]

    for desc, qty, unit_price in page1_items:
        amount = qty * unit_price
        pdf.cell(80, 7, desc)
        pdf.cell(25, 7, str(qty), align="C")
        pdf.cell(35, 7, f"${unit_price:.2f}", align="R")
        pdf.cell(40, 7, f"${amount:.2f}", align="R", new_x="LMARGIN", new_y="NEXT")

    # Footer note on page 1
    pdf.ln(10)
    pdf.set_font("Helvetica", "I", 9)
    pdf.cell(0, 5, "Continued on next page...", new_x="LMARGIN", new_y="NEXT")

    # ---- Page 2: Remaining items + totals ----
    pdf.add_page()

    pdf.set_font("Helvetica", "B", 12)
    pdf.cell(0, 8, f"Invoice {data['invoice_number']} - Page 2", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(4)

    # Table header repeat
    pdf.set_fill_color(60, 60, 100)
    pdf.set_text_color(255, 255, 255)
    pdf.set_font("Helvetica", "B", 10)
    pdf.cell(80, 8, "Description", fill=True)
    pdf.cell(25, 8, "Qty", align="C", fill=True)
    pdf.cell(35, 8, "Unit Price", align="R", fill=True)
    pdf.cell(40, 8, "Amount", align="R", fill=True, new_x="LMARGIN", new_y="NEXT")

    pdf.set_text_color(0, 0, 0)
    pdf.set_font("Helvetica", "", 10)

    for desc, qty, unit_price in page2_items:
        amount = qty * unit_price
        pdf.cell(80, 7, desc)
        pdf.cell(25, 7, str(qty), align="C")
        pdf.cell(35, 7, f"${unit_price:.2f}", align="R")
        pdf.cell(40, 7, f"${amount:.2f}", align="R", new_x="LMARGIN", new_y="NEXT")

    # Separator line
    pdf.ln(6)
    pdf.set_draw_color(100, 100, 100)
    pdf.line(10, pdf.get_y(), 200, pdf.get_y())
    pdf.ln(4)

    # Totals
    pdf.set_font("Helvetica", "", 11)
    x_label = 115
    x_val = 160
    w_val = 40

    pdf.set_x(x_label)
    pdf.cell(45, 7, "Subtotal:")
    pdf.cell(w_val, 7, f"${data['subtotal']:.2f}", align="R", new_x="LMARGIN", new_y="NEXT")

    pdf.set_x(x_label)
    pdf.cell(45, 7, f"Tax ({data['tax_rate'] * 100:.0f}%):")
    pdf.cell(w_val, 7, f"${data['tax']:.2f}", align="R", new_x="LMARGIN", new_y="NEXT")

    pdf.set_font("Helvetica", "B", 12)
    pdf.set_x(x_label)
    pdf.cell(45, 8, "TOTAL:")
    pdf.cell(w_val, 8, f"${data['total']:.2f}", align="R", new_x="LMARGIN", new_y="NEXT")

    pdf.ln(12)
    pdf.set_font("Helvetica", "I", 9)
    pdf.cell(0, 5, "Thank you for your business!", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 5, f"Payment due by {data['due_date']}", align="C", new_x="LMARGIN", new_y="NEXT")

    # Write output
    output_path.parent.mkdir(parents=True, exist_ok=True)
    pdf.output(str(output_path))
    print(f"  ✓ Generated: {output_path}  ({os.path.getsize(output_path)} bytes)")


def main() -> None:
    print("Generating sample invoice PDFs...\n")

    _make_invoice_pdf(CLEAN, HERE / "sample_invoice_clean.pdf")
    _make_invoice_pdf(ANOMALY, HERE / "sample_invoice_anomaly.pdf")

    print("\nDone. PDFs are deterministic and ready for demo.")


if __name__ == "__main__":
    main()
