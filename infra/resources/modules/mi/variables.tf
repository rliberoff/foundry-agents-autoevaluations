variable "resource_group_name" {
  description = "(Required) Project resource group name."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must contain valid, non-empty values of the documented type."
  }
}

variable "location" {
  description = "(Required) Azure region selected by the root module."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must contain valid, non-empty values of the documented type."
  }
}

variable "name" {
  description = "(Required) The name of this User Assigned Managed Identity."
  type        = string
  nullable    = false
}

variable "tags" {
  description = "(Optional) Specifies the tags for this resource."
  type        = map(any)
  nullable    = true
  default     = {}
}
