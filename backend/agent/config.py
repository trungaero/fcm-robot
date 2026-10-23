"""Agent worker configuration.

Secrets arrive as environment variables populated by the deployment (Key Vault
-> VM environment). The agent holds provider keys; the edge never does.
"""

from __future__ import annotations

import os
from dataclasses import dataclass


def _get(name: str, default: str) -> str:
    return os.environ.get(name, default)


def _get_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


@dataclass(frozen=True)
class Settings:
    agent_name: str = _get("AGENT_NAME", "fcm-agent")

    # Private SFU address. Never the public hostname (architecture.md §4.5).
    livekit_url: str = _get("LIVEKIT_URL", "ws://livekit:7880")
    livekit_api_key: str = _get("LIVEKIT_API_KEY", "")
    livekit_api_secret: str = _get("LIVEKIT_API_SECRET", "")

    # Model providers (OpenAI-compatible).
    stt_model: str = _get("STT_MODEL", "gpt-4o-mini-transcribe")
    llm_model: str = _get("LLM_MODEL", "gpt-4o-mini")
    tts_model: str = _get("TTS_MODEL", "gpt-4o-mini-tts")
    tts_voice: str = _get("TTS_VOICE", "alloy")

    model_timeout_seconds: float = _get_float("MODEL_TIMEOUT_SECONDS", 10.0)
    instructions: str = _get(
        "ASSISTANT_INSTRUCTIONS",
        "You are a friendly robot assistant. Keep answers short and speak naturally.",
    )

    database_url: str | None = os.environ.get("DATABASE_URL") or None

    # Fallback reply when a provider times out or is throttled (§8.5).
    fallback_reply: str = _get(
        "FALLBACK_REPLY", "Sorry, I am having trouble reaching my brain right now. Could you say that again?"
    )


settings = Settings()
