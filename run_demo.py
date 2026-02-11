#!/usr/bin/env python3
"""
run_demo.py — One-command demo entry point.

Usage:
  python run_demo.py                      # Direct mode (deterministic, no LLM)
  python run_demo.py --mode agent         # Agent mode (requires OPENAI_API_KEY)
  python run_demo.py --pdf-url <url>      # Custom PDF URL

This script:
1. Starts the parser service in the background
2. Sends a parse request (direct or via OpenAI orchestrator)
3. Prints formatted demo output
4. Shuts down the parser service
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import os
import signal
import subprocess
import sys
import time

import httpx
from dotenv import load_dotenv

load_dotenv()

# Defaults
DEFAULT_PDF_URL = os.getenv(
    "DEMO_PDF_URL", "http://localhost:8000/sample_invoice_anomaly.pdf"
)
PARSER_HOST = "127.0.0.1"
PARSER_PORT = int(os.getenv("PARSER_PORT", "8001"))
PARSER_URL = os.getenv("PARSER_URL", f"http://{PARSER_HOST}:{PARSER_PORT}")
PARSER_API_KEY = os.getenv("PARSER_API_KEY", "demo-api-key-change-me")

SEP = "--------------------------------------------------"


# ============================================================
# Parser service lifecycle
# ============================================================


def start_parser_service() -> subprocess.Popen:
    """Launch the parser FastAPI service as a subprocess."""
    env = os.environ.copy()
    env["PARSER_API_KEY"] = PARSER_API_KEY
    proc = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "uvicorn",
            "parser_service.main:app",
            "--host",
            PARSER_HOST,
            "--port",
            str(PARSER_PORT),
            "--log-level",
            "warning",
        ],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return proc


def wait_for_parser(timeout: float = 15.0) -> bool:
    """Block until parser /health responds or timeout."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            r = httpx.get(f"{PARSER_URL}/health", timeout=2.0)
            if r.status_code == 200:
                return True
        except (httpx.ConnectError, httpx.ReadError):
            pass
        time.sleep(0.3)
    return False


def stop_process(proc: subprocess.Popen) -> None:
    """Gracefully stop a subprocess."""
    if proc.poll() is None:
        if sys.platform == "win32":
            proc.terminate()
        else:
            proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


# ============================================================
# Parser call
# ============================================================


async def call_parser(pdf_url: str) -> dict:
    """Call POST /parse on the parser service."""
    headers = {
        "X-API-Key": PARSER_API_KEY,
        "Content-Type": "application/json",
    }
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(
            f"{PARSER_URL}/parse",
            json={"pdf_url": pdf_url},
            headers=headers,
        )
        resp.raise_for_status()
        return resp.json()


# ============================================================
# Formatted output
# ============================================================


def print_demo_output(pdf_url: str, result: dict, agent_summary: str | None = None) -> None:
    """Print the locked console output format."""
    invoice = result["invoice"]
    warnings = result.get("warnings", [])
    request_id = result["request_id"]
    trace_id = result["trace_id"]
    summary = result.get("summary", "")

    print()
    print(SEP)
    print("\U0001f9fe MULTI-AGENT INVOICE ANALYSIS DEMO")
    print(SEP)
    print()
    print(f"PDF: {pdf_url}")
    print(f"Request ID: {request_id}")
    print(f"Trace ID: {trace_id}")
    print()
    print("Calling Parse Specialist Agent...")
    print("\u2713 Parse complete")
    print()

    # Extracted totals
    print(SEP)
    print("\U0001f4ca EXTRACTED TOTALS")
    print(SEP)
    print(f"Vendor: {invoice['vendor']}")
    print(f"Invoice: {invoice['invoice_number']}")
    print(f"Subtotal: ${invoice['subtotal']:.2f}")
    print(f"Tax: ${invoice['tax']:.2f}")
    print(f"Total: ${invoice['total']:.2f}")
    print()

    # Anomalies
    if warnings:
        print(SEP)
        print("\u26a0\ufe0f ANOMALIES DETECTED")
        print(SEP)
        for i, w in enumerate(warnings, 1):
            print(f"{i}. {w['message']}")
        print()
    else:
        print(SEP)
        print("\u2705 NO ANOMALIES DETECTED")
        print(SEP)
        print()

    # Summary
    print(SEP)
    print("\U0001f9e0 AGENT SUMMARY")
    print(SEP)
    if agent_summary:
        print(agent_summary)
    else:
        print(summary)
    print()

    # Observability
    print(SEP)
    print("\U0001f52d OBSERVABILITY")
    print(SEP)
    print("Trace exported via OpenTelemetry")
    print("Use trace_id above in your dashboard to view full agent chain.")
    print()
    print("Demo complete.")
    print(SEP)


# ============================================================
# Main
# ============================================================


async def run_direct(pdf_url: str) -> None:
    """Direct mode — deterministic, no LLM."""
    result = await call_parser(pdf_url)
    print_demo_output(pdf_url, result)


async def run_agent_mode(pdf_url: str) -> None:
    """Agent mode — uses OpenAI orchestrator."""
    # Set env so orchestrator finds the parser
    os.environ.setdefault("PARSER_URL", PARSER_URL)
    os.environ.setdefault("PARSER_API_KEY", PARSER_API_KEY)

    from orchestrator.agent import run_agent

    result_bundle = await run_agent(pdf_url)
    parser_response = result_bundle.get("parser_response", {})
    agent_summary = result_bundle.get("agent_summary", "")

    # Merge IDs from orchestrator
    parser_response.setdefault("request_id", result_bundle.get("request_id", ""))
    parser_response.setdefault("trace_id", result_bundle.get("trace_id", ""))

    print_demo_output(pdf_url, parser_response, agent_summary=agent_summary or None)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Microsoft + NVIDIA Multi-Agent Invoice Analysis Demo"
    )
    parser.add_argument(
        "--mode",
        choices=["direct", "agent"],
        default="direct",
        help="Execution mode: 'direct' (default, deterministic) or 'agent' (OpenAI)",
    )
    parser.add_argument(
        "--pdf-url",
        default=DEFAULT_PDF_URL,
        help=f"URL of the invoice PDF (default: {DEFAULT_PDF_URL})",
    )
    parser.add_argument(
        "--no-parser",
        action="store_true",
        help="Skip starting the parser service (if already running)",
    )

    args = parser.parse_args()

    # Suppress noisy logs for clean demo output
    logging.basicConfig(level=logging.WARNING)

    parser_proc = None

    try:
        # Start parser service
        if not args.no_parser:
            parser_proc = start_parser_service()
            if not wait_for_parser():
                print("ERROR: Parser service failed to start.", file=sys.stderr)
                if parser_proc:
                    stop_process(parser_proc)
                sys.exit(1)

        # Run demo
        if args.mode == "agent":
            if not os.getenv("OPENAI_API_KEY"):
                print(
                    "ERROR: OPENAI_API_KEY required for agent mode. "
                    "Set it in .env or environment.",
                    file=sys.stderr,
                )
                sys.exit(1)
            asyncio.run(run_agent_mode(args.pdf_url))
        else:
            asyncio.run(run_direct(args.pdf_url))

    except KeyboardInterrupt:
        print("\nInterrupted.")
    except Exception as exc:
        print(f"\nERROR: {exc}", file=sys.stderr)
        sys.exit(1)
    finally:
        if parser_proc:
            stop_process(parser_proc)


if __name__ == "__main__":
    main()
