output "TF_BACKEND_RESOURCE_GROUP_NAME" {
  value       = azurerm_resource_group.state.name
  description = "Resource group that contains the Terraform state Storage Account."
}

output "TF_BACKEND_STORAGE_ACCOUNT_NAME" {
  value       = azurerm_storage_account.state.name
  description = "Storage Account used by the resources-stage remote backend."
}

output "TF_BACKEND_CONTAINER_NAME" {
  value       = azurerm_storage_container.tfstate.name
  description = "Private container used by the resources-stage remote backend."
}

output "TF_BACKEND_SUBSCRIPTION_ID" {
  value       = var.subscription_id
  description = "Azure subscription ID used by the Terraform provider."
}
