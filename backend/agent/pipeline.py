"""Per-session agent pipeline.

Cascaded STT -> LLM -> TTS (architecture.md §9.1). One process per session, as
dispatched by the SFU over the worker WebSocket.
"""

from __future__ import annotations

import asyncio
import logging

from livekit.agents import Agent, AgentSession, AutoSubscribe, JobContext
from livekit.plugins import openai, silero

from config import settings
from persistence import TurnStore

logger = logging.getLogger("fcm.agent.pipeline")


def _turn_detection():
    """Optional semantic turn detector; falls back to VAD-only if unavailable."""
    try:
        from livekit.plugins.turn_detector.multilingual import MultilingualModel

        return MultilingualModel()
    except Exception:  # noqa: BLE001 - optional dependency
        logger.info("turn detector unavailable; using VAD end-of-turn detection")
        return "vad"


class Assistant(Agent):
    def __init__(self) -> None:
        super().__init__(instructions=settings.instructions)


async def entrypoint(ctx: JobContext) -> None:
    """Called once the SFU dispatches a job for a room."""
    worker_id = settings.agent_name
    store = TurnStore(settings.database_url, worker_id)
    await store.start()

    # AUDIO_ONLY: the robot publishes camera too, but vision is opt-in (§2.1).
    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)

    session = AgentSession(
        vad=silero.VAD.load(),
        turn_detection=_turn_detection(),
        stt=openai.STT(model=settings.stt_model),
        llm=openai.LLM(model=settings.llm_model, timeout=settings.model_timeout_seconds),
        tts=openai.TTS(model=settings.tts_model, voice=settings.tts_voice),
    )

    pending_user_text = ""
    assistant_done = asyncio.Event()

    @session.on("conversation_item_added")
    def _on_item(event) -> None:  # noqa: ANN001 - SDK event type
        nonlocal pending_user_text
        item = event.item
        role = getattr(item, "role", None)
        text = (getattr(item, "text_content", None) or "").strip()
        if not text:
            return
        if role == "user":
            pending_user_text = text
        elif role == "assistant":
            store.enqueue_turn(ctx.room.name, pending_user_text, text)
            pending_user_text = ""
            assistant_done.set()

    @session.on("agent_state_changed")
    def _on_state(event) -> None:  # noqa: ANN001 - SDK event type
        # "listening" while "speaking" is a barge-in; the SDK cancels LLM/TTS
        # streams for us, the robot flushes its playback buffer.
        if event.new_state == "listening" and event.old_state == "speaking":
            logger.info("barge-in detected room=%s", ctx.room.name)

    await session.start(room=ctx.room, agent=Assistant())
    await session.generate_reply(
        instructions="Greet the user briefly and ask what they need."
    )

    try:
        await assistant_done.wait()
        logger.info("session ready room=%s", ctx.room.name)
        # Keep the session alive until the room closes; ctx.shutdown() is driven
        # by the job lifecycle.
        await asyncio.Event().wait()
    finally:
        await store.stop()
