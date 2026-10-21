output "application_insights_id" {
  value       = azurerm_application_insights.this.id
  description = "Resource ID of workspace-based Application Insights."
  sensitive   = true
}

output "application_insights_connection_string" {
  value       = azurerm_application_insights.this.connection_string
  description = "Connection string passed only to the Foundry connection's write-only metadata."
  sensitive   = true
  ephemeral   = true
}
