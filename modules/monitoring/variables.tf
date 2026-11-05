# -----------------------------------------------------------------------------
# variables.tf (monitoring module)
# -----------------------------------------------------------------------------
variable "name" {
  description = "Name prefix for all resources, e.g. webapp-prod-primary."
  type        = string
}

variable "region" {
  description = "Region being monitored. Used by the dashboard and the key policy."
  type        = string
}

variable "account_id" {
  description = "AWS account ID. Used in the key policy."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "alarm_email" {
  description = "Address that receives alarm notifications. It must confirm the subscription by email."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alarm_email))
    error_message = "alarm_email must be a valid email address."
  }
}

variable "cluster_name" {
  description = "Name of the ECS cluster."
  type        = string
}

variable "service_name" {
  description = "Name of the ECS service."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the load balancer (alarm and dashboard dimension)."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "ARN suffix of the target group (alarm and dashboard dimension)."
  type        = string
}

variable "min_running_tasks" {
  description = "The alarm fires when fewer tasks than this are running."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Extra tags merged onto resources."
  type        = map(string)
  default     = {}
}
