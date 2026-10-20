output "id" {
  description = "Identifier of the model access service."
  value       = azurerm_cognitive_account.foundry.id
}

output "name" {
  description = "Name of the model access service."
  value       = azurerm_cognitive_account.foundry.name
}

output "endpoint" {
  description = "Service endpoint."
  value       = azurerm_cognitive_account.foundry.endpoint
  sensitive   = true
}

output "project_id" {
  description = "The ID of the Microsoft Foundry project."
  value       = azurerm_cognitive_account_project.project.id
}

output "project_name" {
  description = "Project that groups model deployments."
  value       = azurerm_cognitive_account_project.project.name
}

output "project_endpoint" {
  description = "Project endpoint used by the solution."
  value       = "${trimsuffix(azurerm_cognitive_account.foundry.endpoint, "/")}/api/projects/${azurerm_cognitive_account_project.project.name}"
}
