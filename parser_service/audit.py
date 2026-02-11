"""Structured audit logging for the parser service.

Rules:
- Never log raw PDF content
- Log metadata only
- Structured JSON format
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone


logger = logging.getLogger("parser.audit")


def _emit(event: str, **kwargs) -> None:
    """Emit a structured audit log entry."""
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "service": "parser-service",
        "event": event,
        **kwargs,
    }
    logger.info(json.dumps(entry, default=str))


def log_request_received(request_id: str, pdf_url: str, trace_id: str) -> None:
    _emit(
        "request_received",
        request_id=request_id,
        pdf_url=pdf_url,
        trace_id=trace_id,
    )


def log_parse_completed(
    request_id: str,
    trace_id: str,
    line_item_count: int,
    warning_count: int,
    duration_ms: float,
) -> None:
    _emit(
        "parse_completed",
        request_id=request_id,
        trace_id=trace_id,
        line_item_count=line_item_count,
        warning_count=warning_count,
        duration_ms=round(duration_ms, 2),
    )
