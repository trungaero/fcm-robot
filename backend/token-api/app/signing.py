"""LiveKit JWT issuance and signing-key retrieval.

Key hierarchy:
  * Azure: signing secret lives in Key Vault, read through the Token API's
    managed identity (`DefaultAzureCredential`), cached in memory.
  * Local: falls back to LIVEKIT_API_KEY / LIVEKIT_API_SECRET from the env.

The robot never sees the API secret or any model-provider key.
"""

from __future__ import annotations

import logging
import threading
import time
from datetime import timedelta

from livekit import api

from .config import Settings

logger = logging.getLogger(__name__)

# Signing keys are cached briefly so a Key Vault outage does not stop issuance,
# while a rotation is still picked up within the TTL. Architecture.md §10 asks
# for exactly this behaviour.
CACHE_TTL_SECONDS = 300

_cache: tuple[str, str] | None = None
_cache_expires_at = 0.0
_cache_lock = threading.Lock()


class SigningError(RuntimeError):
    """Raised when no signing credentials can be obtained."""


def _from_key_vault(settings: Settings) -> tuple[str, str]:
    # Imported lazily so local dev does not require Azure libraries to be usable.
    from azure.identity import DefaultAzureCredential
    from azure.keyvault.secrets import SecretClient

    client = SecretClient(vault_url=settings.key_vault_url, credential=DefaultAzureCredential())
    key = client.get_secret(settings.livekit_api_key_secret_name).value
    secret = client.get_secret(settings.livekit_api_secret_secret_name).value
    if not key or not secret:
        raise SigningError("Key Vault returned an empty LiveKit credential")
    return key, secret


def get_signing_credentials(settings: Settings) -> tuple[str, str]:
    global _cache, _cache_expires_at

    now = time.monotonic()
    with _cache_lock:
        if _cache is not None and now < _cache_expires_at:
            return _cache

        if settings.using_key_vault:
            try:
                credentials = _from_key_vault(settings)
            except Exception:  # noqa: BLE001 - log and fall back to cache
                if _cache is not None:
                    logger.exception("key vault read failed; serving cached signing key")
                    return _cache
                raise
        else:
            if not settings.livekit_api_key or not settings.livekit_api_secret:
                raise SigningError("no LiveKit credentials configured")
            credentials = (settings.livekit_api_key, settings.livekit_api_secret)

        _cache = credentials
        _cache_expires_at = now + CACHE_TTL_SECONDS
        return _cache


def room_for(settings: Settings, device_id: str) -> str:
    """Rooms are bound to the device so a token cannot reach another session."""
    return f"{settings.room_prefix}{device_id}"


def issue_token(settings: Settings, device_id: str) -> tuple[str, str, str]:
    """Return (jwt, room, livekit_url) for a device.

    Grants are least-privilege: join one room, publish mic/camera, subscribe.
    No room admin, no data-channel publish, no room list.
    """
    api_key, api_secret = get_signing_credentials(settings)
    room = room_for(settings, device_id)

    token = (
        api.AccessToken(api_key, api_secret)
        .with_identity(f"robot-{device_id}")
        .with_name(device_id)
        .with_ttl(timedelta(seconds=settings.token_ttl_seconds))
        .with_grants(
            api.VideoGrants(
                room_join=True,
                room=room,
                can_publish=True,
                can_publish_data=False,
                can_subscribe=True,
                can_update_own_metadata=False,
                room_admin=False,
            )
        )
        .to_jwt()
    )

    return token, room, settings.livekit_public_url
