"""Runtime configuration for the Token API.

All values come from the environment; on Azure the container app/VM environment
is populated from Key Vault by the deployment, never from a file on disk.
"""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=None, extra="ignore", case_sensitive=False)

    # LiveKit
    livekit_api_key: str = ""
    livekit_api_secret: str = ""
    livekit_public_url: str = "ws://localhost:7880"

    # Key Vault (optional). When unset, the env credentials are used (dev only).
    key_vault_url: str | None = None
    livekit_api_key_secret_name: str = "livekit-api-key"
    livekit_api_secret_secret_name: str = "livekit-api-secret"

    # Token policy
    token_ttl_seconds: int = 900
    room_prefix: str = "device."

    # Device registry (pilot: static env; production: PostgreSQL + attestation)
    device_registry: str = ""
    revoked_devices: str = ""
    rate_limit_per_minute: int = 10
    max_concurrent_sessions_per_device: int = 1

    @property
    def using_key_vault(self) -> bool:
        return bool(self.key_vault_url)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
