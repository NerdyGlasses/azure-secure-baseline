# ---------- Centralized logging ----------
# Fixes: CKV2_AZURE_21 (blob read/write/delete logging)
#
# This also sets up the actual bridge to the Sentinel side of this portfolio: a Log Analytics
# workspace is what Sentinel is built on top of. Pointing diagnostic settings here means these
# logs would be queryable with the KQL detections written separately, not just stored and ignored.

resource "azurerm_log_analytics_workspace" "security" {
  name                = "${var.prefix}-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 90
}

resource "azurerm_monitor_diagnostic_setting" "storage_blob" {
  name                       = "${var.prefix}-storage-blob-diag"
  target_resource_id         = "${azurerm_storage_account.data.id}/blobServices/default/"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.security.id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }

  metric {
    category = "Transaction"
    enabled  = true
  }
}
