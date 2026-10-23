provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    virtual_machine {
      delete_os_disk_on_deletion     = true
      skip_shutdown_and_force_delete = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

data "azurerm_client_config" "current" {}

locals {
  # Short, DNS-safe prefix used in every resource name.
  name_prefix = "${var.prefix}-${var.environment}"

  tags = merge(
    {
      project     = "fcm-robot"
      environment = var.environment
      managed_by  = "terraform"
    },
    var.tags,
  )

  vm_image = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Environment handed to each host. Rendered into cloud-init, so anything here
  # is readable from the instance metadata service: keep real secrets in Key
  # Vault and use a bootstrap step to fetch them before enabling production.
  edge_env = {
    LIVEKIT_API_KEY       = random_string.livekit_key.result
    LIVEKIT_API_SECRET    = random_password.livekit_secret.result
    LIVEKIT_VERSION       = var.livekit_version
    NODE_IP               = cidrhost(var.subnet_edge_prefix, 10)
    LIVEKIT_URL           = "ws://${cidrhost(var.subnet_edge_prefix, 10)}:7880"
    LIVEKIT_PUBLIC_URL    = "wss://${var.domain_livekit}"
    TURN_ENABLED          = var.enable_turn ? "true" : "false"
    TURN_DOMAIN           = var.domain_turn
    TURN_EXTERNAL_TLS     = "true"
    API_DOMAIN            = var.domain_api
    LIVEKIT_DOMAIN        = var.domain_livekit
    TURN_UPSTREAM         = "livekit:5349"
    TOKEN_API_UPSTREAM    = "token-api:8080"
    LIVEKIT_UPSTREAM      = "livekit:7880"
    TOKEN_TTL_SECONDS     = tostring(var.token_ttl_seconds)
    KEY_VAULT_URL         = "https://${azurerm_key_vault.kv.name}.vault.azure.net/"
    DEVICE_REGISTRY       = var.device_registry
    REVOKED_DEVICES       = ""
    RATE_LIMIT_PER_MINUTE = tostring(var.rate_limit_per_minute)
  }
}
