"""Orchestrator configuration — all values from environment."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from dotenv import load_dotenv

load_dotenv()


@dataclass(frozen=True)
class OrchestratorConfig:
    """Immutable configuration loaded once at startup."""

    openai_api_key: str = field(default_factory=lambda: os.getenv("OPENAI_API_KEY", ""))
    openai_model: str = field(default_factory=lambda: os.getenv("OPENAI_MODEL", "gpt-4o"))
    openai_api_base: str = field(default_factory=lambda: os.getenv("OPENAI_API_BASE", ""))
    openai_api_version: str = field(default_factory=lambda: os.getenv("OPENAI_API_VERSION", "2025-03-01-preview"))
    openai_api_type: str = field(default_factory=lambda: os.getenv("OPENAI_API_TYPE", ""))

    parser_url: str = field(default_factory=lambda: os.getenv("PARSER_URL", "http://localhost:8001"))
    parser_api_key: str = field(default_factory=lambda: os.getenv("PARSER_API_KEY", "demo-api-key-change-me"))

    otel_endpoint: str = field(default_factory=lambda: os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", ""))
    log_level: str = field(default_factory=lambda: os.getenv("LOG_LEVEL", "INFO"))


config = OrchestratorConfig()
