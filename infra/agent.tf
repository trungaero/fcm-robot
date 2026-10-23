locals {
  agent_env = {
    AGENT_NAME            = "fcm-agent-${var.environment}"
    LIVEKIT_URL           = "ws://${cidrhost(var.subnet_edge_prefix, 10)}:7880"
    LIVEKIT_API_KEY       = random_string.livekit_key.result
    LIVEKIT_API_SECRET    = random_password.livekit_secret.result
    STT_MODEL             = "gpt-4o-mini-transcribe"
    LLM_MODEL             = "gpt-4o-mini"
    TTS_MODEL             = "gpt-4o-mini-tts"
    TTS_VOICE             = "alloy"
    MODEL_TIMEOUT_SECONDS = "10"
    OPENAI_API_KEY        = var.model_api_key
    DATABASE_URL          = "postgresql://${var.postgres_admin_login}:${random_password.postgres.result}@${azurerm_postgresql_flexible_server.pg.fqdn}:5432/fcm?sslmode=require"
  }
}

resource "azurerm_network_interface" "agent" {
  count = var.agent_vm_count

  name                = "nic-agent-${local.name_prefix}-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.agent.id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(var.subnet_agent_prefix, 20 + count.index)
    # No public IP: outbound goes through the NAT gateway, inbound is denied.
  }
}

resource "azurerm_linux_virtual_machine" "agent" {
  count = var.agent_vm_count

  name                            = "vm-agent-${local.name_prefix}-${count.index}"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  size                            = var.agent_vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  tags                            = local.tags

  network_interface_ids = [azurerm_network_interface.agent[count.index].id]

  identity {
    type = "SystemAssigned"
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = local.vm_image.publisher
    offer     = local.vm_image.offer
    sku       = local.vm_image.sku
    version   = local.vm_image.version
  }

  boot_diagnostics {}

  custom_data = base64encode(
    templatefile("${path.module}/cloud-init/agent.yaml.tftpl", {
      env                = local.agent_env
      repo_url           = var.repo_url
      repo_branch        = var.repo_branch
      tailscale_auth_key = var.tailscale_auth_key
      hostname           = "fcm-agent-${var.environment}-${count.index}"
    })
  )
}
