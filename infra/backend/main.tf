locals {
  suffix = var.suffix == null ? random_string.suffix[0].result : var.suffix
  state_resource_group_name  = "rg-demo-foundry-agents-autoevaluation-terraform-${local.suffix}"
  state_storage_account_name = "sttfstate${local.suffix}"

  tags = merge(var.tags, {
    createdAt = "${formatdate("YYYY-MM-DD hh:mm:ss", timestamp())} UTC"
    purpose   = "Terraform remote state"
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

resource "azurerm_resource_group" "state" {
  name     = local.state_resource_group_name
  location = var.location
  tags     = local.tags

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_storage_account" "state" {
  name                            = local.state_storage_account_name
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "state_blob_contributor" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
