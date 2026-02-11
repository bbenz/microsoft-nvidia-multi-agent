"""Pydantic models for the parser service — locked output contract."""

from __future__ import annotations

from pydantic import BaseModel, Field


class BoundingBox(BaseModel):
    """Normalized bounding box [0..1]."""

    x: float = 0.0
    y: float = 0.0
    w: float = 0.0
    h: float = 0.0
    page: int = 1


class LineItem(BaseModel):
    description: str
    quantity: int = 1
    unit_price: float = 0.0
    amount: float = 0.0
    bbox: BoundingBox = Field(default_factory=BoundingBox)


class Invoice(BaseModel):
    vendor: str = ""
    invoice_date: str = ""
    invoice_number: str = ""
    currency: str = "USD"
    subtotal: float = 0.0
    tax: float = 0.0
    total: float = 0.0
    line_items: list[LineItem] = Field(default_factory=list)


class Warning(BaseModel):
    code: str
    message: str
    details: dict = Field(default_factory=dict)


class ParseResponse(BaseModel):
    request_id: str
    trace_id: str
    invoice: Invoice
    warnings: list[Warning] = Field(default_factory=list)
    summary: str = ""


class ParseRequest(BaseModel):
    pdf_url: str
