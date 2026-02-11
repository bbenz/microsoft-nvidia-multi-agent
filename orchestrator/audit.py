"""Structured audit logging for the orchestrator.

Rules:
- Log tool_call and tool_result events
- Never log raw PDF content
- Metadata only
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone

logger = logging.getLogger("orchestrator.audit")


def _emit(event: str, **kwargs) -> None:
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "service": "orchestrator",
        "event": event,
        **kwargs,
    }
    logger.info(json.dumps(entry, default=str))


def log_tool_call(
    request_id: str,
    tool_name: str,
    arguments: dict,
    trace_id: str = "",
) -> None:
    _emit(
        "tool_call",
        request_id=request_id,
        tool_name=tool_name,
        arguments=arguments,
        trace_id=trace_id,
    )


def log_tool_result(
    request_id: str,
    tool_name: str,
    success: bool,
    warning_count: int = 0,
    trace_id: str = "",
) -> None:
    _emit(
        "tool_result",
        request_id=request_id,
        tool_name=tool_name,
        success=success,
        warning_count=warning_count,
        trace_id=trace_id,
    )
