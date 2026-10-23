"""Per-device and per-IP rate limiting.

In-memory sliding window: correct for a single Token API instance, which is what
the pilot runs. Move to Redis before running more than one replica.
"""

from __future__ import annotations

import time
from collections import defaultdict, deque
from threading import Lock

WINDOW_SECONDS = 60.0


class SlidingWindowLimiter:
    def __init__(self, limit: int, window: float = WINDOW_SECONDS) -> None:
        self._limit = limit
        self._window = window
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    def allow(self, key: str) -> tuple[bool, int]:
        """Return (allowed, retry_after_seconds)."""
        now = time.monotonic()
        cutoff = now - self._window
        with self._lock:
            bucket = self._hits[key]
            while bucket and bucket[0] < cutoff:
                bucket.popleft()
            if len(bucket) >= self._limit:
                retry_after = max(1, int(bucket[0] + self._window - now) + 1)
                return False, retry_after
            bucket.append(now)
            return True, 0
