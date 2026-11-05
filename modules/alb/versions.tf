# -----------------------------------------------------------------------------
# versions.tf
# Modules declare the provider they need but never configure it.
# -----------------------------------------------------------------------------
terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}
