# -----------------------------------------------------------------------------
# variables.tf (dns-failover module)
# -----------------------------------------------------------------------------
variable "name" {
  description = "Name prefix for the health check and alarm, e.g. webapp-prod."
  type        = string
}

variable "hosted_zone_id" {
  description = "ID of the existing Route 53 hosted zone that holds the domain."
  type        = string

  validation {
    condition     = can(regex("^Z[A-Z0-9]{8,31}$", var.hosted_zone_id))
    error_message = "hosted_zone_id must look like Z0123456789ABCDEFGHIJ."
  }
}

variable "domain_name" {
  description = "The name users type, e.g. app.example.com. It must belong to the hosted zone."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be a lowercase fully qualified domain name, e.g. app.example.com."
  }
}

variable "primary_alb_dns_name" {
  description = "DNS name of the primary load balancer."
  type        = string
}

variable "primary_alb_zone_id" {
  description = "Hosted zone ID of the primary load balancer (needed for the alias record)."
  type        = string
}

variable "secondary_alb_dns_name" {
  description = "DNS name of the DR load balancer."
  type        = string
}

variable "secondary_alb_zone_id" {
  description = "Hosted zone ID of the DR load balancer (needed for the alias record)."
  type        = string
}

variable "health_check_path" {
  description = "Path the health checkers request on the primary load balancer."
  type        = string
  default     = "/health"
}

variable "alarm_topic_arn" {
  description = "SNS topic told when the primary is declared unhealthy (a failover is happening)."
  type        = string
}

variable "tags" {
  description = "Extra tags merged onto resources."
  type        = map(string)
  default     = {}
}
