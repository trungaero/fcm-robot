resource "azurerm_public_ip" "edge" {
  name                = "pip-edge-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_interface" "edge" {
  name                = "nic-edge-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.edge.id
    private_ip_address_allocation = "Static"
    # Fixed private address so the agent tier can target the SFU predictably
    # and the SFU can advertise it as its node_ip.
    private_ip_address   = cidrhost(var.subnet_edge_prefix, 10)
    public_ip_address_id = azurerm_public_ip.edge.id
  }
}

resource "azurerm_linux_virtual_machine" "edge" {
  name                            = "vm-edge-${local.name_prefix}"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  size                            = var.edge_vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  tags                            = local.tags

  network_interface_ids = [azurerm_network_interface.edge.id]

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
    templatefile("${path.module}/cloud-init/edge.yaml.tftpl", {
      env                = local.edge_env
      repo_url           = var.repo_url
      repo_branch        = var.repo_branch
      tailscale_auth_key = var.tailscale_auth_key
      hostname           = "fcm-edge-${var.environment}"
    })
  )
}
