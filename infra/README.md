# Infrastructure (Azure)

Terraform for the pilot topology in `../docs/architecture.md`:

- **VM 1** (`snet-edge`) — reverse proxy (443, L4 SNI), Token API, LiveKit SFU + embedded TURN. Static public IP.
- **VM 2** (`snet-agent`) — agent workers. No public IP; egress via NAT gateway.
- **Data tier** (`snet-data`, `snet-endpoints`) — PostgreSQL Flexible Server (delegated subnet), Key Vault and Blob Storage over private endpoints.
- **Observability** — Log Analytics workspace, Azure Monitor agent, metric alerts.
- **Admin** — SSH only from `vpn_admin_cidrs` (Tailscale CGNAT by default); no public 22.

```text
infra/
├── versions.tf            providers + (commented) remote state
├── providers.tf           provider features, tags, shared locals
├── variables.tf           every input, with validation
├── network.tf             VNet, subnets, NAT, NSGs, private DNS zones
├── keyvault.tf            Key Vault, private endpoint, identities, secrets
├── data.tf                PostgreSQL, Blob Storage, private endpoints
├── edge.tf                VM 1: public IP, NIC, VM, cloud-init
├── agent.tf               VM 2(s): NIC, VM, cloud-init
├── observability.tf       Log Analytics, DCA/DCR, alerts, diagnostics
├── outputs.tf             IPs, FQDNs, required DNS records
├── cloud-init/            per-host bootstrap templates
└── terraform.tfvars.example
```

## Apply

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# edit: admin_ssh_public_key, domains, repo_url, tailscale_auth_key

terraform init
terraform fmt -recursive
terraform validate
terraform plan -out tf.plan
terraform apply tf.plan
```

First boot pulls the repo and builds the images on each VM. For anything beyond a
pilot, push images to a registry (or ACR) and set `REGISTRY` / `IMAGE_TAG` in the
host env files instead of building on the host.

## Post-apply checklist

1. **DNS** — create A records for `domain_api`, `domain_livekit`, `domain_turn`
   pointing at `edge_public_ip`. All three share one IP; SNI is what separates them.
2. **Certificates** — issue certificates for the three hostnames with DNS-01 and
   mount them into the proxy. `local_certs` in `backend/proxy/Caddyfile` is a
   development placeholder; ACME HTTP-01 cannot work while layer4 owns port 443.
3. **Schema** — apply the pilot schema from inside the VNet:

   ```bash
   psql "host=$(terraform output -raw postgres_fqdn) dbname=fcm user=fcmadmin sslmode=require" \
     -f ../backend/db/init.sql
   ```

4. **TURN** — confirm `turn.<domain>` reaches port 5349 through the proxy, then
   test a join from a network that blocks UDP entirely.
5. **Agent ICE** — in LiveKit session stats, verify the agent's selected candidate
   is `10.20.1.10`, not the public IP. Hairpinning through the public path adds
   latency and breaks when NAT changes.
6. **Admin** — `ssh` to the private addresses only while connected to the VPN.
7. **Secrets** — once bootstrap is verified, set `key_vault_public_access = false`
   and remove the deployer's `Key Vault Secrets Officer` assignment if a pipeline
   identity takes over.

## Alerts worth adding by hand

Worker-count and join-failure alerts come from LiveKit (`:6789/metrics`), not from
Azure platform metrics. Add scheduled-query alerts in Log Analytics once the
Prometheus scrape is wired up:

- `livekit_workers_registered == 0` for 2 minutes → critical.
- Join failure rate > 5% over 10 minutes → critical.
- Voice-to-voice p95 > 3 s over 15 minutes → high.
- TURN allocation failure spike → high.

## Known limitations (documented, accepted for the pilot)

- **VM 1 is a single point of failure.** Accepted in §14 and revisited before
  production; the mitigation path is multi-node SFU with Redis.
- **Host-local compose builds.** Build time is part of the restart RTO; a
  registry-based rollout is the fix.
- **Secrets in cloud-init.** Bootstrap values are readable from instance
  metadata. Move to Key Vault reads at runtime before production.
- **Static device registry.** `DEVICE_REGISTRY` is a pilot placeholder; replace
  with per-device certificates plus attestation.
