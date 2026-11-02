# -----------------------------------------------------------------------------
# providers.tf
# TWO providers for the same account: one per region.
#
#   aws          the default provider = the primary region
#   aws.dr       an alias = the disaster recovery region
#
# A resource or module uses the default provider unless it says
# `provider = aws.dr` (resources) or `providers = { aws = aws.dr }` (modules).
# Route 53 is global, so it uses the default provider.
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.primary_region

  access_key = var.mock_mode ? "mock-access-key" : null
  secret_key = var.mock_mode ? "mock-secret-key" : null

  skip_credentials_validation = var.mock_mode
  skip_requesting_account_id  = var.mock_mode
  skip_metadata_api_check     = var.mock_mode

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "containerized-app-with-observability-and-DR"
      RegionRole  = "primary"
    }
  }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region

  access_key = var.mock_mode ? "mock-access-key" : null
  secret_key = var.mock_mode ? "mock-secret-key" : null

  skip_credentials_validation = var.mock_mode
  skip_requesting_account_id  = var.mock_mode
  skip_metadata_api_check     = var.mock_mode

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "containerized-app-with-observability-and-DR"
      RegionRole  = "dr"
    }
  }
}
