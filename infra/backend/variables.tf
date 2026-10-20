variable "suffix" {
  description = "(Required) Unique identifier of exactly 5 lowercase letters or digits for this developer's DEV environment."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{5}$", var.suffix))
    error_message = "suffix must contain exactly 5 lowercase letters or digits."
  }
}

variable "location" {
  description = "Azure region for the DEV bootstrap resources."
  type        = string
  nullable    = false
}

variable "subscription_id" {
  description = "Explicit Azure subscription ID for provider operations."
  type        = string
  nullable    = false
}

variable "tags" {
  description = "(Optional) Common tags for the state store resources."
  type        = map(any)
  nullable    = true
  default = {
    createdWith = "Terraform"
    project     = "Demo Microsoft Foundry Agents Auto-evaluations"
  }
}
