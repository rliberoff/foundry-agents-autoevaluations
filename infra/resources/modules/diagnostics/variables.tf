variable "log_analytics_workspace_id" {
  description = "(Required) Destination workspace for resource diagnostics."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/[^/]+/.+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must contain valid, non-empty values of the documented type."
  }
}

variable "target_resource_ids" {
  description = "(Required) Resources whose supported log and metric categories are forwarded to the workspace."
  type        = map(string)
  nullable    = false

  validation {
    condition     = alltrue([for value in values(var.target_resource_ids) : try(length(trimspace(value)) > 0, false)])
    error_message = "target_resource_ids must contain valid, non-empty values of the documented type."
  }
}
