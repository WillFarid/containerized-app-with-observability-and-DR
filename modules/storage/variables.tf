# -----------------------------------------------------------------------------
# variables.tf (storage module)
# -----------------------------------------------------------------------------
variable "name" {
  description = "Name prefix for the keys, role and alarm, e.g. webapp-prod."
  type        = string
}

variable "source_region" {
  description = "Region of the primary bucket."
  type        = string
}

variable "replica_region" {
  description = "Region of the replica bucket (the disaster recovery region)."
  type        = string
}

variable "source_bucket_name" {
  description = "Globally unique name of the primary bucket."
  type        = string
}

variable "replica_bucket_name" {
  description = "Globally unique name of the replica bucket."
  type        = string
}

variable "alarm_topic_arn" {
  description = "SNS topic that is told when replication falls behind."
  type        = string
}

variable "noncurrent_version_days" {
  description = "Days to keep old versions of overwritten or deleted objects. They are what lets you undo a mistake."
  type        = number
  default     = 30
}

variable "force_destroy" {
  description = "Allow Terraform to delete a bucket that still holds objects. Keep false for real data."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags merged onto resources."
  type        = map(string)
  default     = {}
}
