"""Token API - the only public way to obtain room access.

Exchanges a device identity for a short-lived, room-bound LiveKit JWT.
Architecture.md §6.2 and §8.1.
"""

from __future__ import annotations

import json
import logging
import time

from fastapi import FastAPI, Header, HTTPException, Request, Response

from . import devices, signing
from .config import get_settings
from .ratelimit import SlidingWindowLimiter

logging.basicConfig(
    level=logging.INFO,
    format='{"ts":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","msg":%(message)s}',
)
logger = logging.getLogger("token-api")

app = FastAPI(title="FCM Token API", version="1.0.0")

settings = get_settings()
_device_limiter = SlidingWindowLimiter(settings.rate_limit_per_minute)
_ip_limiter = SlidingWindowLimiter(settings.rate_limit_per_minute * 5)


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",", 1)[0].strip()
    return request.client.host if request.client else "unknown"


def _audit(action: str, result: str, device_id: str, source_ip: str, **extra: object) -> None:
    # Never log JWTs, provider keys, or device secrets.
    record = {
        "action": action,
        "result": result,
        "device_id": device_id,
        "source_ip": source_ip,
        **extra,
    }
    logger.info(json.dumps(record, separators=(",", ":")))


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/v1/token")
@app.post("/token")
async def issue_token(
    request: Request,
    response: Response,
    payload: dict | None = None,
    x_device_secret: str | None = Header(default=None, alias="X-Device-Secret"),
) -> dict[str, object]:
    body = payload or {}
    device_id = str(body.get("device_id") or "").strip()
    source_ip = _client_ip(request)

    if not device_id:
        raise HTTPException(status_code=400, detail="device_id is required")

    allowed, retry_after = _ip_limiter.allow(source_ip)
    if not allowed:
        _audit("issue", "ip_rate_limited", device_id, source_ip)
        raise HTTPException(
            status_code=429, detail="too many requests", headers={"Retry-After": str(retry_after)}
        )

    if devices.is_revoked(device_id):
        _audit("issue", "revoked", device_id, source_ip)
        raise HTTPException(status_code=403, detail="device revoked")

    if not devices.is_known(device_id):
        _audit("issue", "unknown_device", device_id, source_ip)
        raise HTTPException(status_code=401, detail="unknown device")

    if not devices.authenticate(device_id, x_device_secret):
        _audit("issue", "bad_credentials", device_id, source_ip)
        raise HTTPException(status_code=401, detail="authentication failed")

    allowed, retry_after = _device_limiter.allow(device_id)
    if not allowed:
        _audit("issue", "device_rate_limited", device_id, source_ip)
        raise HTTPException(
            status_code=429,
            detail="token request rate exceeded",
            headers={"Retry-After": str(retry_after)},
        )

    # Attestation hook. Play Integrity where GMS exists, hardware key
    # attestation / mTLS where it does not (architecture.md §6.1, assumption A3).
    # TODO: verify payload["attestation"] before issuing; reject when required.

    try:
        token, room, url = signing.issue_token(settings, device_id)
    except signing.SigningError:
        _audit("issue", "signing_unavailable", device_id, source_ip)
        raise HTTPException(status_code=503, detail="token signing unavailable") from None

    expires_at = int(time.time()) + settings.token_ttl_seconds
    _audit("issue", "granted", device_id, source_ip, room=room, ttl=settings.token_ttl_seconds)

    # Tokens are bearer credentials: never cache them.
    response.headers["Cache-Control"] = "no-store"
    return {
        "token": token,
        "room": room,
        "url": url,
        "expires_at": expires_at,
        "ttl": settings.token_ttl_seconds,
    }
