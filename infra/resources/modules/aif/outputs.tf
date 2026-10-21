output "name" {
  description = "Name of the model access service."
  value       = azurerm_cognitive_account.foundry.name
}

output "project_id" {
  description = "The ID of the Microsoft Foundry project."
  value       = azurerm_cognitive_account_project.project.id
  sensitive   = true
}

output "project_name" {
  description = "Project that groups model deployments."
  value       = azurerm_cognitive_account_project.project.name
}

output "project_endpoint" {
  description = "Project endpoint used by the solution."
  value       = "https://${azurerm_cognitive_account.foundry.name}.services.ai.azure.com/api/projects/${azurerm_cognitive_account_project.project.name}"
  sensitive   = true
}

output "container_registry_connection_name" {
  description = "Name of the Foundry project connection to the container registry."
  value       = azapi_resource.container_registry_connection.name
}
