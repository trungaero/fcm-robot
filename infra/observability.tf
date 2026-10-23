resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_monitor_action_group" "alerts" {
  count = var.alert_email == "" ? 0 : 1

  name                = "ag-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "fcmalerts"
  tags                = local.tags

  email_receiver {
    name                    = "oncall"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

locals {
  alert_action_group_ids = var.alert_email == "" ? [] : [azurerm_monitor_action_group.alerts[0].id]
}

# ---------------------------------------------------------------------------
# Host metrics and logs
# ---------------------------------------------------------------------------

resource "azurerm_monitor_data_collection_rule" "vms" {
  name                = "dcr-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "Linux"
  tags                = local.tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = "law"
    }
  }

  data_sources {
    performance_counter {
      name                          = "perf"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor(_Total)\\% Processor Time",
        "\\Memory\\Available MBytes",
        "\\LogicalDisk(_Total)\\% Free Space",
        "\\Network Interface(*)\\Bytes Total/sec",
      ]
    }

    syslog {
      name           = "syslog"
      facility_names = ["*"]
      log_levels     = ["Emergency", "Alert", "Critical", "Error", "Warning"]
      streams        = ["Microsoft-Syslog"]
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Syslog"]
    destinations = ["law"]
  }
}

resource "azurerm_virtual_machine_extension" "ama_edge" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.edge.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.29"
  automatic_upgrade_enabled  = true
  auto_upgrade_minor_version = true
  tags                       = local.tags
}

resource "azurerm_virtual_machine_extension" "ama_agent" {
  count = var.agent_vm_count

  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.agent[count.index].id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.29"
  automatic_upgrade_enabled  = true
  auto_upgrade_minor_version = true
  tags                       = local.tags
}

resource "azurerm_monitor_data_collection_rule_association" "edge" {
  name                    = "dcra-edge"
  target_resource_id      = azurerm_linux_virtual_machine.edge.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.vms.id

  depends_on = [azurerm_virtual_machine_extension.ama_edge]
}

resource "azurerm_monitor_data_collection_rule_association" "agent" {
  count = var.agent_vm_count

  name                    = "dcra-agent-${count.index}"
  target_resource_id      = azurerm_linux_virtual_machine.agent[count.index].id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.vms.id

  depends_on = [azurerm_virtual_machine_extension.ama_agent]
}

# ---------------------------------------------------------------------------
# Alerts. The two that matter most for this architecture (architecture.md §11.3)
# are host capacity and losing all registered workers, which is a LiveKit metric
# rather than an Azure metric: see infra/README.md for the query-based alert.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_metric_alert" "edge_cpu" {
  name                = "alert-edge-cpu"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_linux_virtual_machine.edge.id]
  description         = "VM 1 CPU above 85% for 5 minutes"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  dynamic "action" {
    for_each = local.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "agent_cpu" {
  name                = "alert-agent-cpu"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = azurerm_linux_virtual_machine.agent[*].id
  description         = "Agent tier CPU above 85% for 15 minutes - add a worker"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  dynamic "action" {
    for_each = local.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# ---------------------------------------------------------------------------
# Data-tier diagnostics
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "kv" {
  name                       = "diag-kv"
  target_resource_id         = azurerm_key_vault.kv.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category_group = "audit"
  }

  enabled_log {
    category_group = "allLogs"
  }
}

resource "azurerm_monitor_diagnostic_setting" "pg" {
  name                       = "diag-pg"
  target_resource_id         = azurerm_postgresql_flexible_server.pg.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "PostgreSQLLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
