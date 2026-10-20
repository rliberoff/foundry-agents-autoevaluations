resource "azurerm_cognitive_account" "foundry" {
  resource_group_name           = var.resource_group_name
  location                      = var.location
  name                          = var.name
  kind                          = "AIServices"
  sku_name                      = "S0"
  custom_subdomain_name         = var.name
  public_network_access_enabled = true
  project_management_enabled    = true
  tags                          = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

# The Foundry project that groups the agents, model deployments and evaluations of this environment.
resource "azurerm_cognitive_account_project" "project" {
  name                 = var.project_name
  cognitive_account_id = azurerm_cognitive_account.foundry.id
  location             = var.location
  tags                 = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

# rai = Responsible AI
resource "azurerm_cognitive_account_rai_policy" "content_filter" {
  name                 = "Custom"
  cognitive_account_id = azurerm_cognitive_account.foundry.id
  base_policy_name     = "Microsoft.DefaultV2"
  mode                 = "Default"
  tags                 = var.tags

  content_filter {
    name               = "Violence"
    block_enabled      = true
    filter_enabled     = true
    severity_threshold = var.content_filter_prompt_violence_severity_threshold
    source             = "Prompt"
  }

  content_filter {
    name               = "Hate"
    block_enabled      = true
    filter_enabled     = true
    severity_threshold = var.content_filter_prompt_hate_severity_threshold
    source             = "Prompt"
  }

  content_filter {
    name               = "Sexual"
    block_enabled      = true
    filter_enabled     = true
    severity_threshold = var.content_filter_prompt_sexual_severity_threshold
    source             = "Prompt"
  }

  content_filter {
    name               = "SelfHarm"
    block_enabled      = true
    filter_enabled     = true
    severity_threshold = var.content_filter_prompt_self_harm_severity_threshold
    source             = "Prompt"
  }

  content_filter {
    name               = "Violence"
    block_enabled      = true
    filter_enabled     = true
    severity_threshold = var.content_filter_completion_violence_severity_threshold
    source             = "Completion"
  }

  content_filter {
    name               = "Hate"
    block_enabled      = true
    filter_enabled     = true
    severity_threshold = var.content_filter_completion_hate_severity_threshold
    source             = "Completion"
  }

  content_filter {
    name               = "Sexual"
    block_enabled      = true
    filter_enabled     = true
    severity_threshold = var.content_filter_completion_sexual_severity_threshold
    source             = "Completion"
  }

  content_filter {
    name               = "SelfHarm"
    block_enabled      = true
    filter_enabled     = true
    severity_threshold = var.content_filter_completion_self_harm_severity_threshold
    source             = "Completion"
  }

  content_filter {
    name           = "Jailbreak"
    block_enabled  = false
    filter_enabled = true
    source         = "Prompt"
  }

  content_filter {
    name           = "Indirect Attack"
    block_enabled  = false
    filter_enabled = true
    source         = "Prompt"
  }

  content_filter {
    name           = "Protected Material Text"
    block_enabled  = false
    filter_enabled = true
    source         = "Completion"
  }

  content_filter {
    name           = "Protected Material Code"
    block_enabled  = false
    filter_enabled = true
    source         = "Completion"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_cognitive_deployment" "foundry" {
  for_each = { for model in var.models : model.id => model }

  name                 = each.key
  cognitive_account_id = azurerm_cognitive_account.foundry.id

  model {
    format  = "OpenAI"
    name    = each.value.model_name
    version = each.value.model_version
  }

  sku {
    capacity = each.value.sku_tokens_per_minute_capacity
    name     = each.value.sku_name
  }

  rai_policy_name        = azurerm_cognitive_account_rai_policy.content_filter.name
  version_upgrade_option = "OnceNewDefaultVersionAvailable" # Options: NoAutoUpgrade, OnceCurrentVersionExpired, OnceNewDefaultVersionAvailable
}

# Set role assignments for the Foundry resource and its project

data "azurerm_subscription" "current" {}

locals {
  # The Foundry RBAC roles were renamed (`Azure AI User` -> `Foundry User`), so they are referenced by their
  # role definition ID, which is stable across the rename.
  # Reference: https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry
  foundry_user_role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
}

resource "azurerm_role_assignment" "service_principals_role_assignment" {
  for_each = { for i, val in var.identity_service_principal_ids : i => val }

  scope                            = azurerm_cognitive_account.foundry.id
  role_definition_name             = "Cognitive Services OpenAI User"
  principal_id                     = each.value
  skip_service_principal_aad_check = true
  principal_type                   = "ServicePrincipal"
}

resource "azurerm_role_assignment" "service_principals_project_role_assignment" {
  for_each = { for i, val in var.identity_service_principal_ids : i => val }

  scope                            = azurerm_cognitive_account_project.project.id
  role_definition_id               = local.foundry_user_role_definition_id
  principal_id                     = each.value
  skip_service_principal_aad_check = true
  principal_type                   = "ServicePrincipal"
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_cognitive_account.foundry.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
