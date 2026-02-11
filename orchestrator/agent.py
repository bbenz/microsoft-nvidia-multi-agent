"""Orchestrator Agent — Coordinator using OpenAI Responses API.

Provides two execution modes:
1. **Agent mode** (`run_agent`):  Uses OpenAI Responses API with tool-use
   to coordinate the workflow. Requires OPENAI_API_KEY.
2. **Direct mode** (`run_direct`):  Calls the parser service directly
   without an LLM, producing deterministic output for demos.
"""

from __future__ import annotations

import json
import logging
import uuid
from typing import Any

import httpx
from opentelemetry import trace
from opentelemetry.propagate import inject

from orchestrator.audit import log_tool_call, log_tool_result
from orchestrator.config import config
from orchestrator.telemetry import get_tracer, init_telemetry

logger = logging.getLogger("orchestrator")

# ---------------------------------------------------------------------------
# Tools definition for OpenAI Responses API
# ---------------------------------------------------------------------------

PARSE_INVOICE_TOOL = {
    "type": "function",
    "name": "parse_invoice",
    "description": (
        "Parse an invoice PDF and extract line items, totals, and detect anomalies. "
        "Returns structured JSON with invoice data and warnings."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "pdf_url": {
                "type": "string",
                "description": "Public URL of the invoice PDF to parse",
            }
        },
        "required": ["pdf_url"],
        "additionalProperties": False,
    },
}

TOOLS = [PARSE_INVOICE_TOOL]


# ---------------------------------------------------------------------------
# Parser client (shared by both modes)
# ---------------------------------------------------------------------------


async def _call_parser(
    pdf_url: str,
    request_id: str,
    tracer: trace.Tracer,
) -> dict[str, Any]:
    """POST /parse on the parser service with trace propagation."""
    with tracer.start_as_current_span(
        "orchestrator.call_parser",
        attributes={"pdf.url": pdf_url, "request.id": request_id},
    ):
        headers: dict[str, str] = {
            "X-API-Key": config.parser_api_key,
            "X-Request-Id": request_id,
            "Content-Type": "application/json",
        }
        # Inject W3C traceparent
        inject(carrier=headers)

        log_tool_call(
            request_id=request_id,
            tool_name="parse_invoice",
            arguments={"pdf_url": pdf_url},
        )

        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(
                f"{config.parser_url}/parse",
                json={"pdf_url": pdf_url},
                headers=headers,
            )
            resp.raise_for_status()
            result = resp.json()

        log_tool_result(
            request_id=request_id,
            tool_name="parse_invoice",
            success=True,
            warning_count=len(result.get("warnings", [])),
            trace_id=result.get("trace_id", ""),
        )

        return result


# ---------------------------------------------------------------------------
# Mode 1: Direct (deterministic, no LLM)
# ---------------------------------------------------------------------------


async def run_direct(pdf_url: str) -> dict[str, Any]:
    """Call parser directly — deterministic, no OpenAI dependency."""
    tracer = init_telemetry()

    with tracer.start_as_current_span(
        "orchestrator.handle_request",
        attributes={"mode": "direct", "pdf.url": pdf_url},
    ) as span:
        request_id = str(uuid.uuid4())
        trace_id = format(span.get_span_context().trace_id, "032x")

        result = await _call_parser(pdf_url, request_id, tracer)

        return {
            "request_id": request_id,
            "trace_id": trace_id,
            "parser_response": result,
        }


# ---------------------------------------------------------------------------
# Mode 2: Agent (OpenAI Responses API)
# ---------------------------------------------------------------------------


async def run_agent(pdf_url: str) -> dict[str, Any]:
    """Orchestrate via OpenAI Responses API with tool use."""
    from openai import OpenAI

    tracer = init_telemetry()

    with tracer.start_as_current_span(
        "orchestrator.handle_request",
        attributes={"mode": "agent", "pdf.url": pdf_url},
    ) as span:
        request_id = str(uuid.uuid4())
        trace_id = format(span.get_span_context().trace_id, "032x")

        client = OpenAI(api_key=config.openai_api_key)

        user_message = (
            f"Here's a PDF URL: {pdf_url}\n"
            "Extract the line items into JSON and tell me if anything looks off."
        )

        # Step 1: Initial response — model should call parse_invoice tool
        response = client.responses.create(
            model=config.openai_model,
            input=user_message,
            tools=TOOLS,
        )

        # Step 2: Handle tool calls
        parser_result = None
        for output_item in response.output:
            if output_item.type == "function_call" and output_item.name == "parse_invoice":
                args = json.loads(output_item.arguments)
                tool_call_id = output_item.call_id

                # Execute the tool
                parser_result = await _call_parser(
                    args["pdf_url"], request_id, tracer
                )

                # Step 3: Send tool result back to model for summary
                response = client.responses.create(
                    model=config.openai_model,
                    input=[
                        {"role": "user", "content": user_message},
                        output_item,
                        {
                            "type": "function_call_output",
                            "call_id": tool_call_id,
                            "output": json.dumps(parser_result),
                        },
                    ],
                    tools=TOOLS,
                )

        # Extract final text from the model
        agent_summary = ""
        for output_item in response.output:
            if output_item.type == "message":
                for content_block in output_item.content:
                    if hasattr(content_block, "text"):
                        agent_summary += content_block.text

        return {
            "request_id": request_id,
            "trace_id": trace_id,
            "parser_response": parser_result,
            "agent_summary": agent_summary,
        }
