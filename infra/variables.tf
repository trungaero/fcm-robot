# ---------------------------------------------------------------------------
# Identity and naming
# ---------------------------------------------------------------------------

variable "prefix" {
  description = "Short name prefix for all resources."
  type        = string
  default     = "fcmrobot"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,10}$", var.prefix))
    error_message = "prefix must be 3-11 lowercase alphanumeric characters."
  }
}

variable "environment" {
  description = "Environment suffix (pilot, staging, prod)."
  type        = string
  default     = "pilot"
}

variable "location" {
  description = "Azure region. Keep it close to both robots and model endpoints."
  type        = string
  default     = "southeastasia"
}

variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Access
# ---------------------------------------------------------------------------

variable "admin_username" {
  description = "Local admin account on both VMs (SSH key only)."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the admin account. Password auth is disabled."
  type        = string
}

variable "vpn_admin_cidrs" {
  description = "Source CIDRs allowed to reach 22/tcp (Tailscale CGNAT range, or WireGuard peers). Empty disables public SSH entirely."
  type        = list(string)
  default     = ["100.64.0.0/10"]
}

variable "enable_wireguard" {
  description = "Open 51820/udp for a self-hosted WireGuard hub. Tailscale needs no inbound rule."
  type        = bool
  default     = false
}

variable "tailscale_auth_key" {
  description = "Optional Tailscale auth key injected into cloud-init. Visible in instance metadata: treat as short-lived."
  type        = string
  default     = ""
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "VNet address space."
  type        = list(string)
  default     = ["10.20.0.0/16"]
}

variable "subnet_edge_prefix" {
  description = "VM 1 subnet (public ingress via NSG)."
  type        = string
  default     = "10.20.1.0/24"
}

variable "subnet_agent_prefix" {
  description = "VM 2 subnet (no public IP, outbound via NAT gateway)."
  type        = string
  default     = "10.20.2.0/24"
}

variable "subnet_data_prefix" {
  description = "Delegated subnet for PostgreSQL Flexible Server."
  type        = string
  default     = "10.20.3.0/24"
}

variable "subnet_endpoint_prefix" {
  description = "Private endpoints for Key Vault and Blob Storage."
  type        = string
  default     = "10.20.4.0/24"
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

variable "edge_vm_size" {
  description = "VM 1 size. Media forwarding is latency-sensitive, not CPU-heavy."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "agent_vm_size" {
  description = "VM 2 size. Size for concurrent conversations plus model I/O."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "agent_vm_count" {
  description = "Number of agent VMs. Workers scale horizontally behind one SFU."
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------------
# Domains and TURN
# ---------------------------------------------------------------------------

variable "domain_api" {
  description = "Hostname for the Token API (e.g. api.example.com)."
  type        = string
}

variable "domain_livekit" {
  description = "Hostname for LiveKit signaling (e.g. livekit.example.com)."
  type        = string
}

variable "domain_turn" {
  description = "Dedicated TURN hostname. Required for L4 SNI routing on 443."
  type        = string
}

variable "enable_turn" {
  description = "Enable the embedded TURN server. Required for restrictive networks."
  type        = bool
  default     = true
}

variable "livekit_version" {
  description = "livekit-server image tag. Verify config keys against the release."
  type        = string
  default     = "v1.9.0"
}

# ---------------------------------------------------------------------------
# Deployment source
# ---------------------------------------------------------------------------

variable "repo_url" {
  description = "Git URL cloned by cloud-init on both VMs."
  type        = string
}

variable "repo_branch" {
  description = "Branch to deploy."
  type        = string
  default     = "main"
}

# ---------------------------------------------------------------------------
# Data tier
# ---------------------------------------------------------------------------

variable "postgres_sku" {
  description = "PostgreSQL Flexible Server SKU."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "PostgreSQL storage in MB."
  type        = number
  default     = 32768
}

variable "postgres_admin_login" {
  description = "PostgreSQL administrator login."
  type        = string
  default     = "fcmadmin"
}

variable "key_vault_public_access" {
  description = "Allow public network access to Key Vault. Set false once Terraform runs from inside the VNet."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Application settings
# ---------------------------------------------------------------------------

variable "token_ttl_seconds" {
  description = "LiveKit JWT lifetime."
  type        = number
  default     = 900

  validation {
    condition     = var.token_ttl_seconds >= 120 && var.token_ttl_seconds <= 3600
    error_message = "token_ttl_seconds must be between 120 and 3600."
  }
}

variable "rate_limit_per_minute" {
  description = "Token requests allowed per device per minute."
  type        = number
  default     = 10
}

variable "device_registry" {
  description = "Pilot static device registry: 'id:secret,id:secret'. Replace with cert/attestation before production."
  type        = string
  default     = "robot-001:change-me-robot-001"
  sensitive   = true
}

variable "model_api_key" {
  description = "Model provider key handed to the agent tier only."
  type        = string
  default     = ""
  sensitive   = true
}

variable "alert_email" {
  description = "Email address for the action group. Leave empty to skip alert routing."
  type        = string
  default     = ""
}
