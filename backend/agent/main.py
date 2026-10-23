"""Agent worker entrypoint.

`python main.py start` registers the worker with the SFU over WSS, reports
availability, and accepts job dispatches. Registration, room signaling and
media all stay inside the VNet (architecture.md §4.5).
"""

from __future__ import annotations

import logging
import sys

from livekit.agents import WorkerOptions, cli

from config import settings
from pipeline import entrypoint

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)


def main() -> None:
    missing = [
        name
        for name, value in (
            ("LIVEKIT_API_KEY", settings.livekit_api_key),
            ("LIVEKIT_API_SECRET", settings.livekit_api_secret),
        )
        if not value
    ]
    if missing:
        sys.exit(f"missing required environment variables: {', '.join(missing)}")

    if settings.livekit_url.startswith(("ws://livekit.", "wss://livekit.")) and "example.com" in settings.livekit_url:
        logging.warning("LIVEKIT_URL looks public; agents should use the private SFU address")

    cli.run_app(
        WorkerOptions(
            entrypoint_fnc=entrypoint,
            agent_name=settings.agent_name,
            # Registration is outbound only, so no public port is needed.
            ws_url=settings.livekit_url,
            api_key=settings.livekit_api_key,
            api_secret=settings.livekit_api_secret,
        )
    )


if __name__ == "__main__":
    main()
