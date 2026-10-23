resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# ---------------------------------------------------------------------------
# Virtual network
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = var.vnet_address_space
  tags                = local.tags
}

resource "azurerm_subnet" "edge" {
  name                 = "snet-edge"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_edge_prefix]
}

resource "azurerm_subnet" "agent" {
  name                 = "snet-agent"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_agent_prefix]
}

resource "azurerm_subnet" "data" {
  name                 = "snet-data"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_data_prefix]

  delegation {
    name = "postgres-flexible"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "endpoints" {
  name                              = "snet-endpoints"
  resource_group_name               = azurerm_resource_group.rg.name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_endpoint_prefix]
  private_endpoint_network_policies = "Disabled"
}

# ---------------------------------------------------------------------------
# Outbound NAT for the private agent subnet.
# Azure default outbound access is retired for new VMs, so the agent tier needs
# an explicit egress path for model APIs, Key Vault and Blob.
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "nat" {
  name                = "nat-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "nat" {
  nat_gateway_id       = azurerm_nat_gateway.nat.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "agent" {
  subnet_id      = azurerm_subnet.agent.id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}

# ---------------------------------------------------------------------------
# NSGs (architecture.md §5.6)
# ---------------------------------------------------------------------------

locals {
  edge_inbound_rules = merge(
    {
      # 443/tcp carries HTTPS, WSS signaling and TURN/TLS (routed by SNI).
      allow-https = { priority = 100, protocol = "Tcp", ports = "443", source = "Internet" }
      # Direct media path for robots that can reach the SFU without TURN.
      allow-media = { priority = 110, protocol = "*", ports = "3478,7881,7882", source = "Internet" }
      # Agent registration, signaling and media stay private.
      allow-agent = { priority = 120, protocol = "*", ports = "7880-7882", source = var.subnet_agent_prefix }
    },
    length(var.vpn_admin_cidrs) > 0 ? {
      allow-admin-ssh = { priority = 130, protocol = "Tcp", ports = "22", source = join(",", var.vpn_admin_cidrs) }
    } : {},
    var.enable_wireguard ? {
      allow-wireguard = { priority = 140, protocol = "Udp", ports = "51820", source = "Internet" }
    } : {},
  )
}

resource "azurerm_network_security_group" "edge" {
  name                = "nsg-edge-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_network_security_rule" "edge_inbound" {
  for_each = local.edge_inbound_rules

  name                        = each.key
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.edge.name
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = each.value.protocol
  source_port_range           = "*"
  destination_port_range      = each.value.ports
  source_address_prefix       = each.value.source
  destination_address_prefix  = "*"
}

resource "azurerm_network_security_rule" "edge_deny_all" {
  name                        = "deny-all-inbound"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.edge.name
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}

resource "azurerm_subnet_network_security_group_association" "edge" {
  subnet_id                 = azurerm_subnet.edge.id
  network_security_group_id = azurerm_network_security_group.edge.id
}

resource "azurerm_network_security_group" "agent" {
  name                = "nsg-agent-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_network_security_rule" "agent_deny_internet" {
  name                        = "deny-internet-inbound"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.agent.name
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
}

resource "azurerm_network_security_rule" "agent_admin_ssh" {
  count = length(var.vpn_admin_cidrs) > 0 ? 1 : 0

  name                        = "allow-admin-ssh"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.agent.name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = var.vpn_admin_cidrs
  destination_address_prefix  = "*"
}

# Explicit egress so a future deny-by-default outbound rule does not break the tier.
resource "azurerm_network_security_rule" "agent_outbound" {
  for_each = {
    model-apis = { priority = 100, ports = "443", destination = "Internet" }
    sfu        = { priority = 110, ports = "7880-7882", destination = var.subnet_edge_prefix }
    database   = { priority = 120, ports = "5432", destination = var.subnet_data_prefix }
  }

  name                        = "allow-${each.key}-outbound"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.agent.name
  priority                    = each.value.priority
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = each.value.ports
  source_address_prefix       = "*"
  destination_address_prefix  = each.value.destination
}

resource "azurerm_subnet_network_security_group_association" "agent" {
  subnet_id                 = azurerm_subnet.agent.id
  network_security_group_id = azurerm_network_security_group.agent.id
}

resource "azurerm_network_security_group" "data" {
  name                = "nsg-data-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_network_security_rule" "data_postgres" {
  name                        = "allow-agent-postgres"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.data.name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "5432"
  source_address_prefix       = var.subnet_agent_prefix
  destination_address_prefix  = "*"
}

resource "azurerm_network_security_rule" "data_deny_all" {
  name                        = "deny-all-inbound"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.data.name
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}

resource "azurerm_subnet_network_security_group_association" "data" {
  subnet_id                 = azurerm_subnet.data.id
  network_security_group_id = azurerm_network_security_group.data.id
}

# ---------------------------------------------------------------------------
# Private DNS zones for private endpoints and PostgreSQL
# ---------------------------------------------------------------------------

locals {
  private_dns_zones = {
    keyvault = "privatelink.vaultcore.azure.net"
    blob     = "privatelink.blob.core.windows.net"
    postgres = "privatelink.postgres.database.azure.com"
  }
}

resource "azurerm_private_dns_zone" "zone" {
  for_each = local.private_dns_zones

  name                = each.value
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "zone" {
  for_each = local.private_dns_zones

  name                  = "link-${each.key}-${local.name_prefix}"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.zone[each.key].name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = local.tags
}
