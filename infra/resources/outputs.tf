output "AZURE_RESOURCE_GROUP" {
  description = "Resource group used by azd for agent deployment."
  value       = azurerm_resource_group.rg.name
}

output "AZURE_TENANT_ID" {
  description = "Microsoft Entra tenant used for deployment."
  value       = data.azurerm_client_config.current.tenant_id
  sensitive   = true
}

output "AZURE_CONTAINER_REGISTRY_ENDPOINT" {
  description = "Container registry login server used by azd."
  value       = module.acr.container_registry_login_server
  sensitive   = true
}

output "AZURE_CONTAINER_REGISTRY_RESOURCE_ID" {
  description = "Resource ID of the container registry used by azd."
  value       = module.acr.container_registry_id
  sensitive   = true
}

output "AZURE_AI_ACCOUNT_NAME" {
  description = "Foundry account hosting the agent project."
  value       = module.aif.name
}

output "AZURE_AI_PROJECT_NAME" {
  description = "Foundry project hosting the agent."
  value       = module.aif.project_name
}

output "AZURE_AI_PROJECT_ID" {
  description = "Resource ID of the Foundry project used by azd."
  value       = module.aif.project_id
  sensitive   = true
}

output "FOUNDRY_PROJECT_ENDPOINT" {
  description = "Foundry project endpoint consumed by the Foundry azd extension."
  value       = module.aif.project_endpoint
  sensitive   = true
}

output "AZURE_AI_PROJECT_ACR_CONNECTION_NAME" {
  description = "Foundry project connection used to pull the hosted agent image."
  value       = module.aif.container_registry_connection_name
}

output "AZURE_AI_MODEL_DEPLOYMENT_NAME" {
  description = "Model deployment used by the hosted demo agent."
  value       = var.foundry_models[0].id
}
