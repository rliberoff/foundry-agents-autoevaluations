locals {
  resource_names = {
    resource_group = "rg-demo-foundry-agents-autoevaluation-${var.suffix}"
    mi             = "mi-demo-foundry-agents-autoevaluation-${var.suffix}"
    log            = "log-demo-foundry-agents-autoevaluation-${var.suffix}"
    appi           = "appi-demo-foundry-agents-autoevaluation-${var.suffix}"
    acr            = "acrdemofoundryagentsautoevaluation${var.suffix}"
    aif            = "aif-demo-foundry-agents-autoevaluation-${var.suffix}"
    aif_project    = "proj-demo-foundry-agents-autoevaluation-${var.suffix}"
  }

  tags = merge(var.tags, {
    createdAt = "${formatdate("YYYY-MM-DD hh:mm:ss", timestamp())} UTC"
    suffix    = var.suffix
  })
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = local.resource_names.resource_group
  location = var.location
  tags     = local.tags

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

module "mi" {
  source              = "./modules/mi"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  tags                = local.tags
  name                = local.resource_names.mi
}

module "log" {
  source              = "./modules/log"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  name                = local.resource_names.log
  tags                = local.tags
}

module "appi" {
  source                     = "./modules/appi"
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = var.location
  name                       = local.resource_names.appi
  log_analytics_workspace_id = module.log.workspace_id
  role_assignments = {
    "application_insights"        = { principal_id = module.mi.identity_principal_id, role_definition_name = "Monitoring Metrics Publisher" }
    "application_insights_reader" = { principal_id = module.mi.identity_principal_id, role_definition_name = "Reader" }
  }
  tags = local.tags
}

module "acr" {
  source                     = "./modules/acr"
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = var.location
  name                       = local.resource_names.acr
  identity_id                = module.mi.identity_id
  log_analytics_workspace_id = module.log.workspace_id
  role_assignments = {
    "acr_pull" = { principal_id = module.mi.identity_principal_id, role_definition_name = "AcrPull" }
  }
  tags = local.tags
}

module "aif" {
  source                                 = "./modules/aif"
  resource_group_name                    = azurerm_resource_group.rg.name
  location                               = var.location
  name                                   = local.resource_names.aif
  identity_id                            = module.mi.identity_id
  identity_service_principal_ids         = [module.mi.identity_principal_id]
  deployment_principal_id                = data.azurerm_client_config.current.object_id
  identity_client_id                     = module.mi.identity_client_id
  container_registry_id                  = module.acr.container_registry_id
  container_registry_endpoint            = module.acr.container_registry_login_server
  application_insights_id                = module.appi.application_insights_id
  application_insights_connection_string = module.appi.application_insights_connection_string
  project_name                           = local.resource_names.aif_project
  models                                 = var.foundry_models
  log_analytics_workspace_id             = module.log.workspace_id
  tags                                   = local.tags
}
