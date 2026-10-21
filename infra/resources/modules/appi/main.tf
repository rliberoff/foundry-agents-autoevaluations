resource "azurerm_application_insights" "this" {
  resource_group_name          = var.resource_group_name
  name                         = var.name
  location                     = var.location
  application_type             = "web"
  workspace_id                 = var.log_analytics_workspace_id
  local_authentication_enabled = false
  internet_ingestion_enabled   = true
  tags                         = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

module "diagnostics" {
  source                     = "../diagnostics"
  log_analytics_workspace_id = var.log_analytics_workspace_id
  target_resource_ids = {
    application_insights = azurerm_application_insights.this.id
  }
}

resource "azurerm_role_assignment" "application" {
  for_each                         = var.role_assignments
  scope                            = azurerm_application_insights.this.id
  role_definition_name             = each.value.role_definition_name
  principal_id                     = each.value.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
