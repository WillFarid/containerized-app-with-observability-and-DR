# -----------------------------------------------------------------------------
# variables.tf (ecs-service module)
# -----------------------------------------------------------------------------
variable "name" {
  description = "Name prefix for all resources, e.g. webapp-prod-primary. IAM is global, so it must be unique per copy."
  type        = string
}

variable "region" {
  description = "Region this copy runs in. Used for log settings and reported by the app."
  type        = string
}

variable "vpc_id" {
  description = "VPC the tasks run in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets (one per AZ) where tasks run."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "Use subnets in at least 2 availability zones."
  }
}

variable "alb_sg_id" {
  description = "Security group of the load balancer. It is the only source allowed to reach the tasks."
  type        = string
}

variable "target_group_arn" {
  description = "Load balancer target group the service registers tasks with."
  type        = string
}

variable "image" {
  description = "Full image reference including a version tag, e.g. <repository-url>:1.0.0. Never use latest."
  type        = string

  validation {
    condition     = !endswith(var.image, ":latest")
    error_message = "Do not deploy the latest tag. Use an explicit version so every deployment is reproducible."
  }
}

variable "app_port" {
  description = "Port the app listens on."
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory in MiB. Must be a valid pair with cpu."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Starting number of tasks. Autoscaling adjusts it afterwards."
  type        = number
  default     = 2
}

variable "log_retention_days" {
  description = "How long to keep container logs in CloudWatch."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Extra tags merged onto resources."
  type        = map(string)
  default     = {}
}

variable "account_id" {
  description = "AWS account ID. Used to build the exact ARN pattern of the secret."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "secret_name" {
  description = "Name of the Secrets Manager secret injected into the container as APP_SECRET. It must exist in this region."
  type        = string
}

variable "secret_kms_key_arn" {
  description = "ARN of the customer-managed key that encrypts the secret. null when the secret uses the AWS-managed key (as the DR replica does)."
  type        = string
  default     = null
}
