# -----------------------------------------------------------------------------
# variables.tf
# More variables are added as each step needs them.
# -----------------------------------------------------------------------------
variable "project" {
  description = "Project name, used in resource names and tags."
  type        = string
  default     = "webapp"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project))
    error_message = "Project must be 3-20 characters: lowercase letters, numbers, hyphens."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "prod"
}

variable "primary_region" {
  description = "Region that normally serves traffic."
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "Disaster recovery region. Must differ from the primary region."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = var.dr_region != var.primary_region
    error_message = "dr_region must be a different region from primary_region, otherwise there is no disaster recovery."
  }
}

variable "mock_mode" {
  description = "true = fake credentials and no calls to AWS (offline plan). false for a real deployment."
  type        = bool
  default     = true
}
