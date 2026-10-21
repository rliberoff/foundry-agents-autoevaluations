output "identity_id" {
  value       = azurerm_user_assigned_identity.this.id
  description = "Resource ID of the Web App user-assigned identity."
  sensitive   = true
}

output "identity_client_id" {
  value       = azurerm_user_assigned_identity.this.client_id
  description = "Client ID of the Web App user-assigned identity."
}

output "identity_principal_id" {
  value       = azurerm_user_assigned_identity.this.principal_id
  description = "Principal ID of the Web App user-assigned identity."
}
