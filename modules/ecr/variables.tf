# -----------------------------------------------------------------------------
# variables.tf (ecr module)
# -----------------------------------------------------------------------------
variable "name" {
  description = "Name prefix for the key and tags, e.g. webapp-prod-primary."
  type        = string
}

variable "repository_name" {
  description = "Name of the image repository, e.g. webapp-prod/app."
  type        = string
}

variable "replication_region" {
  description = "Region to copy every pushed image to automatically. null = no replication."
  type        = string
  default     = null
}

variable "account_id" {
  description = "AWS account ID. Needed only to name the replication destination."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "tags" {
  description = "Extra tags merged onto resources."
  type        = map(string)
  default     = {}
}
