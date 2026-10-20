variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group for the Microsoft Foundry resource."
  type        = string
  nullable    = false
}

variable "location" {
  description = "(Required) Specifies the location of the Microsoft Foundry resource."
  type        = string
  nullable    = false
}

variable "name" {
  description = "(Required) Specifies the name of the Microsoft Foundry resource. It is also used as its custom subdomain, so it must be globally unique."
  type        = string
  nullable    = false
}

variable "project_name" {
  description = "(Optional) Specifies the name of the Microsoft Foundry project to create in this resource. Defaults to `Elecnor`."
  type        = string
  nullable    = false
  default     = "proj-foundry-agents-autoevaluation"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_.-]{1,63}$", var.project_name))
    error_message = "The project name must be between 2 and 64 characters long, start with a letter or a digit, and contain only letters, digits, underscores, dots or hyphens."
  }
}

variable "identity_id" {
  description = "(Required) Specifies a the ID of a User Assigned Managed Identities to be associated with this resource."
  type        = string
  nullable    = false
}

variable "identity_service_principal_ids" {
  description = "(Optional) Specifies a list Service Principal IDs for proper role assigments associated with this resource."
  type        = list(string)
  nullable    = false
  default     = []
}

variable "models" {
  description = "(Optional) Specifies the list of models to deploy into this Microsoft Foundry resource."
  type = list(object({
    # The ID of the model to deploy (a.k.a. the deployment name)
    id = string

    # The name of the model to deploy
    model_name = string

    # The version of the model to deploy
    model_version = string

    # The SKU name. Valid values currently are `Standard` and `Global-Standard`
    sku_name = string

    # The maximum number of tokens per minute for the deployed model, specified in thousands.
    sku_tokens_per_minute_capacity = number
  }))
  nullable = false
  default  = []

  validation {
    condition     = length(var.models) == length(distinct([for model in var.models : model.id]))
    error_message = "Each model ID must be unique."
  }

  validation {
    condition     = alltrue([for model in var.models : contains(["Standard", "DataZoneBatch", "DataZoneStandard", "DataZoneProvisionedManaged", "GlobalBatch", "GlobalProvisionedManaged", "GlobalStandard", "ProvisionedManaged"], model.sku_name)])
    error_message = "The SKU name is invalid. Check the valid values for the deployed model."
  }
}

variable "content_filter_prompt_violence_severity_threshold" {
  description = "(Optional) Specifies the severity threshold for the violence content filter on prompts in Azure OpenAI. Possible values are `Low`, `Medium`and `High`. Defaults to `Low`."
  type        = string
  nullable    = false
  default     = "Low"

  validation {
    condition     = can(regex("^(Low|Medium|High)$", var.content_filter_prompt_violence_severity_threshold))
    error_message = "The severity threshold must be either `Low`, `Medium` or `High`."
  }
}

variable "content_filter_prompt_hate_severity_threshold" {
  description = "(Optional) Specifies the severity threshold for the hate content filter on prompts in Azure OpenAI. Possible values are `Low`, `Medium`and `High`. Defaults to `Low`."
  type        = string
  nullable    = false
  default     = "Low"

  validation {
    condition     = can(regex("^(Low|Medium|High)$", var.content_filter_prompt_hate_severity_threshold))
    error_message = "The severity threshold must be either `Low`, `Medium` or `High`."
  }
}

variable "content_filter_prompt_sexual_severity_threshold" {
  description = "(Optional) Specifies the severity threshold for the sexual content filter on prompts in Azure OpenAI. Possible values are `Low`, `Medium`and `High`. Defaults to `Low`."
  type        = string
  nullable    = false
  default     = "Low"

  validation {
    condition     = can(regex("^(Low|Medium|High)$", var.content_filter_prompt_sexual_severity_threshold))
    error_message = "The severity threshold must be either `Low`, `Medium` or `High`."
  }
}

variable "content_filter_prompt_self_harm_severity_threshold" {
  description = "(Optional) Specifies the severity threshold for the self-harm content filter on prompts in Azure OpenAI. Possible values are `Low`, `Medium`and `High`. Defaults to `Low`."
  type        = string
  nullable    = false
  default     = "Low"

  validation {
    condition     = can(regex("^(Low|Medium|High)$", var.content_filter_prompt_self_harm_severity_threshold))
    error_message = "The severity threshold must be either `Low`, `Medium` or `High`."
  }
}

variable "content_filter_completion_violence_severity_threshold" {
  description = "(Optional) Specifies the severity threshold for the violence content filter on completions in Azure OpenAI. Possible values are `Low`, `Medium`and `High`. Defaults to `Low`."
  type        = string
  nullable    = false
  default     = "Low"

  validation {
    condition     = can(regex("^(Low|Medium|High)$", var.content_filter_completion_violence_severity_threshold))
    error_message = "The severity threshold must be either `Low`, `Medium` or `High`."
  }
}

variable "content_filter_completion_hate_severity_threshold" {
  description = "(Optional) Specifies the severity threshold for the hate content filter on completions in Azure OpenAI. Possible values are `Low`, `Medium`and `High`. Defaults to `Low`."
  type        = string
  nullable    = false
  default     = "Low"

  validation {
    condition     = can(regex("^(Low|Medium|High)$", var.content_filter_completion_hate_severity_threshold))
    error_message = "The severity threshold must be either `Low`, `Medium` or `High`."
  }
}

variable "content_filter_completion_sexual_severity_threshold" {
  description = "(Optional) Specifies the severity threshold for the sexual content filter on completions in Azure OpenAI. Possible values are `Low`, `Medium`and `High`. Defaults to `Low`."
  type        = string
  nullable    = false
  default     = "Low"

  validation {
    condition     = can(regex("^(Low|Medium|High)$", var.content_filter_completion_sexual_severity_threshold))
    error_message = "The severity threshold must be either `Low`, `Medium` or `High`."
  }
}

variable "content_filter_completion_self_harm_severity_threshold" {
  description = "(Optional) Specifies the severity threshold for the self-harm content filter on completions in Azure OpenAI. Possible values are `Low`, `Medium`and `High`. Defaults to `Low`."
  type        = string
  nullable    = false
  default     = "Low"

  validation {
    condition     = can(regex("^(Low|Medium|High)$", var.content_filter_completion_self_harm_severity_threshold))
    error_message = "The severity threshold must be either `Low`, `Medium` or `High`."
  }
}

variable "log_analytics_workspace_id" {
  description = "(Required) Log Analytics workspace to which diagnostics are sent (FR-041)."
  type        = string
  nullable    = false
}

variable "tags" {
  description = "(Optional) Specifies the tags for this resource."
  type        = map(any)
  nullable    = true
  default     = {}
}

