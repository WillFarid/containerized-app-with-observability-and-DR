# -----------------------------------------------------------------------------
# variables.tf (secrets module)
# -----------------------------------------------------------------------------
variable "name" {
  description = "Name prefix for the key and tags, e.g. webapp-prod."
  type        = string
}

variable "secret_name" {
  description = "Name of the secret, e.g. webapp-prod/app-secret. The same name exists in the replica region."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9/_+=.@-]{1,512}$", var.secret_name))
    error_message = "secret_name may contain letters, numbers and /_+=.@- only, up to 512 characters."
  }
}

variable "replica_region" {
  description = "Region that receives a read-only copy of the secret, kept in sync automatically. null = no replica."
  type        = string
  default     = null
}

variable "recovery_window_in_days" {
  description = "Days a deleted secret can still be recovered (7 to 30)."
  type        = number
  default     = 30

  validation {
    condition     = var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30
    error_message = "recovery_window_in_days must be between 7 and 30."
  }
}

variable "tags" {
  description = "Extra tags merged onto resources."
  type        = map(string)
  default     = {}
}
