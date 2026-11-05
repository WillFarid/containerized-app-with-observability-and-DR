# -----------------------------------------------------------------------------
# variables.tf (alb module)
# -----------------------------------------------------------------------------
variable "name" {
  description = "Name prefix for all resources, e.g. webapp-prod-primary."
  type        = string
}

variable "vpc_id" {
  description = "VPC the target group and security group belong to."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets (one per AZ) where the load balancer runs."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "An ALB needs subnets in at least 2 availability zones."
  }
}

variable "app_port" {
  description = "Port the app listens on. The target group forwards here."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "HTTP path the load balancer calls to decide if a task is healthy."
  type        = string
  default     = "/health"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener. Certificates are regional."
  type        = string
}

variable "ssl_policy" {
  description = "TLS policy for the HTTPS listener (TLS 1.3 with 1.2 fallback)."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "enable_deletion_protection" {
  description = "Block accidental deletion of the load balancer."
  type        = bool
  default     = true
}

variable "access_logs_bucket_name" {
  description = "Globally unique name for the S3 bucket that stores access logs."
  type        = string
}

variable "access_logs_retention_days" {
  description = "Days to keep access logs before S3 deletes them."
  type        = number
  default     = 365
}

variable "logs_force_destroy" {
  description = "Allow Terraform to delete the log bucket even if it has logs. Keep false in production."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags merged onto resources."
  type        = map(string)
  default     = {}
}
