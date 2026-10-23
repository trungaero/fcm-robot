"""Turn persistence.

Writes are best-effort and never block the audio path (architecture.md §8.5):
a failed insert is retried with backoff and then dropped with a log line.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any

import asyncpg

logger = logging.getLogger("fcm.agent.persistence")

_UPSERT_SESSION = """
INSERT INTO sessions (room_name, device_id, agent_worker_id, region)
VALUES ($1, $2, $3, $4)
ON CONFLICT (room_name) DO UPDATE SET agent_worker_id = EXCLUDED.agent_worker_id
RETURNING session_id
"""

_INSERT_TURN = """
INSERT INTO turns (session_id, seq, user_text, assistant_text, barge_in)
VALUES ($1, COALESCE((SELECT MAX(seq) + 1 FROM turns WHERE session_id = $1), 1), $2, $3, $4)
"""


class TurnStore:
    def __init__(self, dsn: str | None, worker_id: str, region: str = "pilot") -> None:
        self._dsn = dsn
        self._worker_id = worker_id
        self._region = region
        self._pool: asyncpg.Pool | None = None
        self._queue: asyncio.Queue[dict[str, Any] | None] = asyncio.Queue(maxsize=1000)
        self._task: asyncio.Task[None] | None = None

    async def start(self) -> None:
        if not self._dsn:
            logger.warning("DATABASE_URL not set; turns will not be persisted")
            return
        self._pool = await asyncpg.create_pool(self._dsn, min_size=1, max_size=4)
        self._task = asyncio.create_task(self._consume(), name="turn-writer")

    async def stop(self) -> None:
        if self._task is None:
            return
        await self._queue.put(None)
        await self._task
        if self._pool is not None:
            await self._pool.close()

    def enqueue_turn(self, room_name: str, user_text: str, assistant_text: str, barge_in: bool = False) -> None:
        if self._dsn is None:
            return
        try:
            self._queue.put_nowait(
                {
                    "room_name": room_name,
                    "user_text": user_text,
                    "assistant_text": assistant_text,
                    "barge_in": barge_in,
                }
            )
        except asyncio.QueueFull:
            logger.warning("turn queue full; dropping turn for room=%s", room_name)

    async def _consume(self) -> None:
        assert self._queue is not None
        while True:
            item = await self._queue.get()
            if item is None:
                return
            await self._write(item)

    async def _write(self, item: dict[str, Any]) -> None:
        if self._pool is None:
            return
        for attempt in range(3):
            try:
                async with self._pool.acquire() as conn:
                    session_id = await conn.fetchval(
                        _UPSERT_SESSION,
                        item["room_name"],
                        item["room_name"].removeprefix("device."),
                        self._worker_id,
                        self._region,
                    )
                    await conn.execute(
                        _INSERT_TURN,
                        session_id,
                        item["user_text"],
                        item["assistant_text"],
                        item["barge_in"],
                    )
                return
            except Exception:  # noqa: BLE001 - persistence must not break audio
                if attempt == 2:
                    logger.exception("failed to persist turn for room=%s", item["room_name"])
                    return
                await asyncio.sleep(0.5 * (2**attempt))
