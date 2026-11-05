# -----------------------------------------------------------------------------
# versions.tf (backup module)
# Builds a vault in each of two regions, so it expects a second provider
# configuration named "aws.dr". The caller passes: providers = { aws = aws, aws.dr = aws.dr }.
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
