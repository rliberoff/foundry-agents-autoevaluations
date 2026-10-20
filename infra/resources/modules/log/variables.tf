variable "resource_group_name" {
  description = "(Required) The resource group where to deploy this Azure Log Workspace Analytics resource."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must contain valid, non-empty values of the documented type."
  }
}

variable "location" {
  description = "(Required) Azure region where to deploy this Azure Log Workspace Analytics resource."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must contain valid, non-empty values of the documented type."
  }
}

variable "name" {
  description = "(Required) The name of this Azure Log Workspace Analytics resource."
  type        = string
  nullable    = false
}

variable "tags" {
  description = "(Optional) Specifies the tags for this resource."
  type        = map(any)
  nullable    = true
  default     = {}
}

variable "retention_days" {
  description = "(Optional) Log Analytics retention in days. Defaults to 30."
  type        = number
  nullable    = false
  default     = 30

  validation {
    condition     = contains([30, 31, 60, 90, 120, 180, 270, 365, 550, 730], var.retention_days)
    error_message = "Log Analytics retention must be one of the supported retention periods."
  }
}
