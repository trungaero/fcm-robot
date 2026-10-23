# FCM Robot

Voice-and-vision robot: Android frontend, LiveKit SFU on Azure, LiveKit agent workers for inference.

| Path | Contents |
| --- | --- |
| `docs/architecture.md` | Approved pilot architecture (source of truth for design decisions) |
| `backend/` | Containerized services + `docker-compose.yml` |
| `infra/` | Terraform for the Azure pilot deployment (VM 1 edge, VM 2 agent, data tier) |

## Backend services

| Service | Purpose | Port(s) |
| --- | --- | --- |
| `livekit` | SFU + embedded TURN | 7880/tcp, 7881/tcp, 7882/udp, 3478/udp, 5349/tcp |
| `token-api` | Device auth → short-lived scoped LiveKit JWT | 8080/tcp |
| `agent` | Agent worker: VAD, turn logic, STT→LLM→TTS, persistence | outbound only |
| `proxy` | L4 SNI routing on 443 (TURN/TLS vs HTTP) | 443/tcp, 80/tcp |

## Quick start (local)

```bash
cd backend
cp .env.example .env      # fill in LIVEKIT_API_KEY / LIVEKIT_API_SECRET / model keys
docker compose up -d --build
curl -s -X POST localhost:8080/v1/token \
  -H 'content-type: application/json' \
  -H 'x-device-secret: change-me-robot-001' \
  -d '{"device_id":"robot-001"}'
```

## Deploy to Azure

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # set ssh key, domains, repo URL
terraform init
terraform plan -out tf.plan
terraform apply tf.plan
```

See `infra/README.md` for the post-apply steps (SQL schema, certificates, VPN access).
