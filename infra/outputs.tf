output "resource_group" {
  description = "Resource group holding the pilot."
  value       = azurerm_resource_group.rg.name
}

output "edge_public_ip" {
  description = "Static public IP for DNS: api.<domain>, livekit.<domain>, turn.<domain>."
  value       = azurerm_public_ip.edge.ip_address
}

output "edge_private_ip" {
  description = "Private address the agent tier and SFU advertise."
  value       = cidrhost(var.subnet_edge_prefix, 10)
}

output "agent_private_ips" {
  description = "Agent VM addresses (private only)."
  value       = [for nic in azurerm_network_interface.agent : nic.private_ip_address]
}

output "livekit_signaling_url" {
  description = "Public WSS endpoint for robots (through the proxy)."
  value       = "wss://${var.domain_livekit}"
}

output "token_api_url" {
  description = "Public HTTPS token endpoint."
  value       = "https://${var.domain_api}/token"
}

output "key_vault_name" {
  description = "Key Vault holding LiveKit and database secrets."
  value       = azurerm_key_vault.kv.name
}

output "postgres_fqdn" {
  description = "Private PostgreSQL hostname (resolves only inside the VNet)."
  value       = azurerm_postgresql_flexible_server.pg.fqdn
}

output "postgres_database" {
  description = "Application database name."
  value       = azurerm_postgresql_flexible_server_database.fcm.name
}

output "recordings_storage_account" {
  description = "Storage account for optional recordings (no shared keys)."
  value       = azurerm_storage_account.recordings.name
}

output "dns_records_required" {
  description = "Create these A records at your DNS provider."
  value = {
    (var.domain_api)     = azurerm_public_ip.edge.ip_address
    (var.domain_livekit) = azurerm_public_ip.edge.ip_address
    (var.domain_turn)    = azurerm_public_ip.edge.ip_address
  }
}

output "admin_ssh_commands" {
  description = "Administration is VPN-only; run these while connected to the VPN."
  value = [
    "ssh ${var.admin_username}@${cidrhost(var.subnet_edge_prefix, 10)}",
    "ssh ${var.admin_username}@${cidrhost(var.subnet_agent_prefix, 20)}",
  ]
}

output "next_steps" {
  description = "Manual work that Terraform intentionally does not do."
  value = [
    "Create DNS A records for api/livekit/turn pointing at ${azurerm_public_ip.edge.ip_address}.",
    "Apply backend/db/init.sql to ${azurerm_postgresql_flexible_server.pg.fqdn} as ${var.postgres_admin_login}.",
    "Issue certificates for the three hostnames (DNS-01) and mount them into the proxy.",
    "Verify agent media selects a private ICE candidate, and TURN works from a UDP-blocked network.",
  ]
}
