"""Pilot device registry.

This is deliberately the simplest thing that can work: a static map of
device_id -> shared secret held in the environment. Replace with:

  * per-device X.509 certificates (Android Keystore / hardware-backed key),
  * attestation verification (Play Integrity, or key attestation without GMS),
  * a `devices` table with a `revoked_at` column read on every request.

The interface (`authenticate` / `is_revoked`) is what the rest of the app uses,
so swapping the backend does not touch the API layer.
"""

from __future__ import annotations

import hmac
from functools import lru_cache

from .config import get_settings


def _parse_pairs(raw: str) -> dict[str, str]:
    pairs: dict[str, str] = {}
    for entry in filter(None, (chunk.strip() for chunk in raw.split(","))):
        if ":" not in entry:
            continue
        device_id, secret = entry.split(":", 1)
        device_id = device_id.strip()
        if device_id:
            pairs[device_id] = secret.strip()
    return pairs


@lru_cache(maxsize=1)
def _registry() -> dict[str, str]:
    return _parse_pairs(get_settings().device_registry)


@lru_cache(maxsize=1)
def _revoked() -> frozenset[str]:
    settings = get_settings()
    return frozenset(
        chunk.strip() for chunk in settings.revoked_devices.split(",") if chunk.strip()
    )


def is_revoked(device_id: str) -> bool:
    return device_id in _revoked()


def is_known(device_id: str) -> bool:
    return device_id in _registry()


def authenticate(device_id: str, presented_secret: str | None) -> bool:
    """Constant-time credential check.

    A missing secret is treated as a failure, never as an anonymous request.
    """
    if not presented_secret or not device_id:
        return False
    expected = _registry().get(device_id)
    if expected is None:
        # Compare against a dummy value so unknown devices are not distinguishable
        # by timing alone.
        hmac.compare_digest(presented_secret, "x" * 32)
        return False
    return hmac.compare_digest(presented_secret, expected)
