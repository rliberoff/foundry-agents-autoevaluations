resource "azurerm_log_analytics_workspace" "this" {
  tags                         = var.tags
  name                         = var.name
  resource_group_name          = var.resource_group_name
  location                     = var.location
  sku                          = "PerGB2018"
  retention_in_days            = var.retention_days
  local_authentication_enabled = false

  lifecycle {
    ignore_changes = [tags]
  }
}

module "diagnostics" {
  source                     = "../diagnostics"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  target_resource_ids        = { log_analytics_workspace = azurerm_log_analytics_workspace.this.id }
}
