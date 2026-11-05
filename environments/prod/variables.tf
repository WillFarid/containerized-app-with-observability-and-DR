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

variable "primary_azs" {
  description = "Availability zones in the primary region. Passed in (not looked up) so plan works without AWS credentials."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "dr_azs" {
  description = "Availability zones in the disaster recovery region."
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

variable "primary_vpc_cidr" {
  description = "Address range of the primary VPC. Must be a /16."
  type        = string
  default     = "10.10.0.0/16"

  validation {
    condition     = can(cidrhost(var.primary_vpc_cidr, 0)) && endswith(var.primary_vpc_cidr, "/16")
    error_message = "primary_vpc_cidr must be a valid /16 CIDR block, e.g. 10.10.0.0/16."
  }
}

variable "dr_vpc_cidr" {
  description = "Address range of the DR VPC. Must be a /16 and must not overlap the primary VPC."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.dr_vpc_cidr, 0)) && endswith(var.dr_vpc_cidr, "/16")
    error_message = "dr_vpc_cidr must be a valid /16 CIDR block, e.g. 10.20.0.0/16."
  }

  # Two /16 ranges overlap only if they are the same network. Keeping the ranges
  # distinct means the two regions could be connected later (peering or a
  # transit gateway) without renumbering anything.
  validation {
    condition     = cidrhost(var.dr_vpc_cidr, 0) != cidrhost(var.primary_vpc_cidr, 0)
    error_message = "dr_vpc_cidr overlaps primary_vpc_cidr. Use a different range for the DR region."
  }
}

variable "account_id" {
  description = "AWS account ID. The default is a documentation placeholder so plan works offline. A real deployment sets TF_VAR_account_id."
  type        = string
  default     = "123456789012"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
