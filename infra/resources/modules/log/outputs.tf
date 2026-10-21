output "workspace_id" {
  value       = azurerm_log_analytics_workspace.this.id
  description = "Resource ID of the selected Azure Log Analytics Workspace."
  sensitive   = true
}
