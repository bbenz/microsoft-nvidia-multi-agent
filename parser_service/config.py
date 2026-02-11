"""Parser service configuration — all values from environment."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from dotenv import load_dotenv

load_dotenv()


@dataclass(frozen=True)
class ParserConfig:
    """Immutable configuration loaded once at startup."""

    api_key: str = field(default_factory=lambda: os.getenv("PARSER_API_KEY", "demo-api-key-change-me"))

    # NVIDIA NIM
    nim_endpoint: str = field(default_factory=lambda: os.getenv("NIM_ENDPOINT", ""))
    nim_model_id: str = field(default_factory=lambda: os.getenv("NIM_MODEL_ID", "nvidia/nemotron-parse"))
    nim_api_key: str = field(default_factory=lambda: os.getenv("NIM_API_KEY", ""))

    # Observability
    otel_endpoint: str = field(default_factory=lambda: os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", ""))
    log_level: str = field(default_factory=lambda: os.getenv("LOG_LEVEL", "INFO"))

    @property
    def mock_mode(self) -> bool:
        """True when no real NIM endpoint is configured."""
        return not self.nim_endpoint


config = ParserConfig()
