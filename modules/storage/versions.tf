# -----------------------------------------------------------------------------
# versions.tf (storage module)
# This module builds resources in TWO regions, so it declares that it expects a
# second provider configuration named "aws.dr". The caller maps its own
# providers onto them: providers = { aws = aws, aws.dr = aws.dr }.
# -----------------------------------------------------------------------------
terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.70"
      configuration_aliases = [aws.dr]
    }
  }
}
