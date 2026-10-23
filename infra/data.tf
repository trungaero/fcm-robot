resource "random_password" "postgres" {
  length      = 32
  special     = true
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 1
  # Avoid characters that need URL encoding in the connection string.
  override_special = "-_"
}

# ---------------------------------------------------------------------------
# PostgreSQL Flexible Server - private access only.
# ---------------------------------------------------------------------------

resource "azurerm_postgresql_flexible_server" "pg" {
  name                          = "psql-${local.name_prefix}-${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  version                       = "16"
  delegated_subnet_id           = azurerm_subnet.data.id
  private_dns_zone_id           = azurerm_private_dns_zone.zone["postgres"].id
  administrator_login           = var.postgres_admin_login
  administrator_password        = random_password.postgres.result
  sku_name                      = var.postgres_sku
  storage_mb                    = var.postgres_storage_mb
  zone                          = "1"
  backup_retention_days         = 7
  geo_redundant_backup_enabled  = false
  public_network_access_enabled = false

  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }

  lifecycle {
    ignore_changes = [zone, high_availability]
  }

  tags = local.tags
}

resource "azurerm_postgresql_flexible_server_database" "fcm" {
  name      = "fcm"
  server_id = azurerm_postgresql_flexible_server.pg.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ---------------------------------------------------------------------------
# Blob Storage for optional recordings. Public access is off; the agent writes
# with its managed identity only (architecture.md §7.3).
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "recordings" {
  name                            = "st${substr(replace(local.name_prefix, "-", ""), 0, 10)}${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false
  shared_access_key_enabled       = false
  is_hns_enabled                  = false

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-blob-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.endpoints.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = azurerm_storage_account.recordings.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.zone["blob"].id]
  }
}

resource "azurerm_storage_container" "recordings" {
  name                  = "recordings"
  storage_account_id    = azurerm_storage_account.recordings.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "agent_blob_contributor" {
  count = var.agent_vm_count

  scope                = azurerm_storage_account.recordings.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_virtual_machine.agent[count.index].identity[0].principal_id
}
