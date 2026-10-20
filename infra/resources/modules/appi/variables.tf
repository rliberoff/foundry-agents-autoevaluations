variable "resource_group_name" {
  description = "(Required) The resource group name where this Application Insights instance will be created."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must contain valid, non-empty values of the documented type."
  }
}

variable "location" {
  description = "(Required) Azure region where this Application Insights instance will be created."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must contain valid, non-empty values of the documented type."
  }
}

variable "name" {
  description = "(Required) The name of this Application Insights instance."
  type        = string
  nullable    = false
}

variable "log_analytics_workspace_id" {
  description = "(Required) Destination Azure Log Analytics Workspace unique identifier for resource diagnostics."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/[^/]+/.+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must contain valid, non-empty values of the documented type."
  }
}

variable "role_assignments" {
  description = "(Optional) Service-scoped data roles keyed by a stable assignment name."
  type        = map(object({ principal_id = string, role_definition_name = string }))
  nullable    = false
  default     = {}

  validation {
    condition     = alltrue([for assignment in values(var.role_assignments) : can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", assignment.principal_id)) && try(length(trimspace(assignment.role_definition_name)) > 0, false)])
    error_message = "role_assignments must contain valid, non-empty values of the documented type."
  }
}

variable "tags" {
  description = "(Optional) Specifies the tags for this resource."
  type        = map(any)
  nullable    = true
  default     = {}
}
