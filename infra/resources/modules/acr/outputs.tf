output "container_registry_id" {
  value       = azurerm_container_registry.this.id
  description = "Resource ID of Azure Container Registry."
  sensitive   = true
}

output "container_registry_login_server" {
  value       = azurerm_container_registry.this.login_server
  description = "ACR login server endpoint."
  depends_on  = [azurerm_role_assignment.this]
  sensitive   = true
}
