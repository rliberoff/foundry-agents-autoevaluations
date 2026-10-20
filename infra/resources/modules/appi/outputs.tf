output "application_insights_id" {
  value       = azurerm_application_insights.this.id
  description = "Resource ID of workspace-based Application Insights."
}

output "application_insights_name" {
  value       = azurerm_application_insights.this.name
  description = "Name of workspace-based Application Insights."
}
