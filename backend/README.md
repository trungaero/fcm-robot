# Backend

Containerized services for the FCM Robot pilot. See `../docs/architecture.md`
for the design and the reasoning behind each component.

```text
backend/
├── docker-compose.yml        # local stack (postgres, livekit, token-api, agent, optional proxy)
├── .env.example              # every setting, documented
├── db/init.sql               # pilot schema (architecture.md §7.2)
├── livekit/                  # SFU + embedded TURN
│   ├── Dockerfile
│   ├── docker-entrypoint.sh  # renders the config from env
│   └── livekit.tpl.yaml
├── token-api/                # device auth -> short-lived scoped JWT
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app/{config,devices,ratelimit,signing,main}.py
├── agent/                    # LiveKit agent worker
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── config.py
│   ├── main.py               # worker registration
│   ├── pipeline.py           # VAD -> STT -> LLM -> TTS per session
│   └── persistence.py        # async, non-blocking turn writes
└── proxy/                    # L4 SNI router on 443 (TURN/TLS vs HTTPS/WSS)
    ├── Dockerfile            # caddy + caddy-l4
    └── Caddyfile
```

## Local run

```bash
cp .env.example .env
docker compose up -d --build
docker compose logs -f livekit
```

Get a token and check the SFU is reachable:

```bash
curl -s -X POST http://localhost:8080/v1/token \
  -H 'content-type: application/json' \
  -H 'x-device-secret: change-me-robot-001' \
  -d '{"device_id":"robot-001"}' | jq
```

## Build the images individually

```bash
docker build -t fcm/livekit:dev   ./livekit
docker build -t fcm/token-api:dev ./token-api
docker build -t fcm/agent:dev     ./agent
docker build -t fcm/proxy:dev     ./proxy
```

## Port plan

| Port | Service | Exposure |
| --- | --- | --- |
| 443/tcp | proxy (SNI: `turn.` passthrough, `api.`/`livekit.` terminated) | public |
| 7880/tcp | LiveKit signaling | private only in production |
| 7881/tcp | ICE-TCP | public (VM 1) |
| 7882/udp | WebRTC media | public (VM 1) |
| 3478/udp | TURN/UDP | public (VM 1) |
| 5349/tcp | TURN/TLS origin | localhost only (published by the proxy) |
| 8080/tcp | Token API | private, behind the proxy |
| 6789/tcp | Prometheus metrics | private |

## Before real users

- Replace the static `DEVICE_REGISTRY` with per-device certificates/attestation
  and a `devices` table checked on every request.
- Set `TURN_ENABLED=true` with a real `TURN_DOMAIN` and certificates.
- Point `LIVEKIT_URL` at the private SFU address for agents and verify in stats
  that the selected ICE candidate is private.
- Move rate limiting to Redis before running more than one Token API replica.
