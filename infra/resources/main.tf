locals {
  suffix = var.suffix == null ? random_string.suffix[0].result : var.suffix

  resource_names = {
    suffix         = local.suffix
    resource_group = "rg-demo-foundry-agents-autoevaluation-${local.suffix}"
    mi             = "mi-demo-foundry-agents-autoevaluation-${local.suffix}"
    log            = "log-demo-foundry-agents-autoevaluation-${local.suffix}"
    appi           = "appi-demo-foundry-agents-autoevaluation-${local.suffix}"
    acr            = "acrdemofoundryagentsautoevaluation${local.suffix}"
    aif            = "aif-demo-foundry-agents-autoevaluation-${local.suffix}"
    aif_project    = "proj-demo-foundry-agents-autoevaluation-${local.suffix}"
  }

  tags = merge(var.tags, {
    createdAt = "${formatdate("YYYY-MM-DD hh:mm:ss", timestamp())} UTC"
    suffix    = local.suffix
  })
}

resource "random_string" "suffix" {
  count = var.suffix == null ? 1 : 0

  length    = 5
  lower     = true
  min_lower = 1
  numeric   = true
  special   = false
  upper     = false
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
