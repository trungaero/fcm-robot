resource "random_string" "livekit_key" {
  length  = 12
  special = false
}

# No special characters: the value is substituted into livekit.yaml by sed.
resource "random_password" "livekit_secret" {
  length  = 44
  special = false
}

resource "azurerm_key_vault" "kv" {
  name                       = substr("kv-${local.name_prefix}-${random_string.suffix.result}", 0, 24)
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
  tags                       = local.tags

  public_network_access_enabled = var.key_vault_public_access

  network_acls {
    default_action = var.key_vault_public_access ? "Allow" : "Deny"
    bypass         = "AzureServices"
  }
}

resource "azurerm_private_endpoint" "kv" {
  name                = "pe-kv-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.endpoints.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-kv"
    private_connection_resource_id = azurerm_key_vault.kv.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "kv-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.zone["keyvault"].id]
  }
}

# ---------------------------------------------------------------------------
# Workload identities.
# Each VM gets its own system-assigned identity; nothing is shared between the
# internet-facing edge and the agent tier (architecture.md §6.3).
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "edge_kv_secrets" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.edge.identity[0].principal_id
}

resource "azurerm_role_assignment" "agent_kv_secrets" {
  count = var.agent_vm_count

  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.agent[count.index].identity[0].principal_id
}

# Lets Terraform (the deploying principal) write secrets. Remove after bootstrap
# if a separate pipeline identity owns secret management.
resource "azurerm_role_assignment" "deployer_kv_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "livekit_api_key" {
  name         = "livekit-api-key"
  value        = random_string.livekit_key.result
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.deployer_kv_officer]
}

resource "azurerm_key_vault_secret" "livekit_api_secret" {
  name         = "livekit-api-secret"
  value        = random_password.livekit_secret.result
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.deployer_kv_officer]
}

resource "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgres-admin-password"
  value        = random_password.postgres.result
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.deployer_kv_officer]
}
