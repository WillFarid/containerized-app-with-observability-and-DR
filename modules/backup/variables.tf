# -----------------------------------------------------------------------------
# variables.tf (backup module)
# -----------------------------------------------------------------------------
variable "name" {
  description = "Name prefix for all resources, e.g. webapp-prod."
  type        = string
}

variable "source_region" {
  description = "Region of the primary vault and of the protected bucket."
  type        = string
}

variable "account_id" {
  description = "AWS account ID. Used in the notification key policy."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "bucket_arn" {
  description = "ARN of the bucket to back up."
  type        = string
}

variable "bucket_kms_key_arns" {
  description = "ARNs of the keys that encrypt the bucket (primary and replica). The backup role needs them to read and restore the data."
  type        = list(string)
}

variable "alarm_email" {
  description = "Address that receives backup failure notifications. It must confirm the subscription by email."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alarm_email))
    error_message = "alarm_email must be a valid email address."
  }
}

variable "continuous_retention_days" {
  description = "How far back point-in-time restore reaches (S3 allows at most 35)."
  type        = number
  default     = 35

  validation {
    condition     = var.continuous_retention_days >= 1 && var.continuous_retention_days <= 35
    error_message = "Continuous backup retention for S3 is 1 to 35 days."
  }
}

variable "monthly_retention_days" {
  description = "How long the monthly long-term backups are kept."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Extra tags merged onto resources."
  type        = map(string)
  default     = {}
}
