# General

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
  description = "(Required) EU Azure region for the project resources."
  type        = string
  nullable    = false

  validation {
    condition = contains([
      "austriaeast", "belgiumcentral", "denmarkeast", "finlandcentral",
      "francecentral", "francesouth", "germanynorth", "germanywestcentral",
      "italynorth", "northeurope", "polandcentral", "spaincentral",
      "swedencentral", "swedensouth", "westeurope",
    ], var.location)
    error_message = "location must be an Azure region within the European Union."
  }
}

variable "foundry_models" {
  description = "(Optional) Models to deploy. Capacity is parameterized per environment so that multiple environments fit within the regional quota (FR-010, FR-010a)."
  type = list(object({
    id                             = string
    model_name                     = string
    model_version                  = string
    sku_name                       = string
    sku_tokens_per_minute_capacity = number
  }))
  nullable = false
  default = [
    {
      id                             = "gpt-6-luna"
      model_name                     = "gpt-6-luna"
      model_version                  = "2026-09-22"
      sku_name                       = "DataZoneStandard"
      sku_tokens_per_minute_capacity = 100
    },
    {
      id                             = "gpt-6.1-sol"
      model_name                     = "gpt-6.1-sol"
      model_version                  = "2026-09-29"
      sku_name                       = "DataZoneStandard"
      sku_tokens_per_minute_capacity = 100
    }
  ]

  validation {
    condition     = length(var.foundry_models) > 0
    error_message = "At least one model deployment is required for the hosted demo agent."
  }
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
