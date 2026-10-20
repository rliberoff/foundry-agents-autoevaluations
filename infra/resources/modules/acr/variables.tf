variable "resource_group_name" {
  description = "(Required) The resource group name where to deploy this Azure Container Registry."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must contain valid, non-empty values of the documented type."
  }
}

variable "location" {
  description = "(Required) Azure region for this Azure Container Registry."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must contain valid, non-empty values of the documented type."
  }
}

variable "name" {
  description = "(Required) Globally unique name for this Azure Container Registry."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name must contain valid, non-empty values of the documented type."
  }
}

variable "identity_id" {
  description = "(Required) Identifier of the managed identity associated with the resource."
  type        = string
  nullable    = false
}

variable "admin_enabled" {
  description = "(Optional) Enables the registry administrator user. It must remain disabled: the expected access is via managed identity, without credentials subject to rotation."
  type        = bool
  nullable    = false
  default     = false
}

variable "sku" {
  description = "(Optional) Service tier of this Azure Container Registry."
  type        = string
  nullable    = false
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be one of 'Basic', 'Standard', or 'Premium'."
  }
}

variable "log_analytics_workspace_id" {
  description = "(Required) Destination workspace for resource diagnostics."
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
