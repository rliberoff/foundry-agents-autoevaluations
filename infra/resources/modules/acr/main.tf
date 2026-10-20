resource "azurerm_container_registry" "this" {
  tags                          = var.tags
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.sku
  admin_enabled                 = var.admin_enabled
  public_network_access_enabled = true
  network_rule_bypass_option    = "AzureServices"

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_role_assignment" "this" {
  for_each                         = var.role_assignments
  scope                            = azurerm_container_registry.this.id
  role_definition_name             = each.value.role_definition_name
  principal_id                     = each.value.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

module "diagnostics" {
  source                     = "../diagnostics"
  log_analytics_workspace_id = var.log_analytics_workspace_id
  target_resource_ids = {
    container_registry = azurerm_container_registry.this.id
  }
}
