# -----------------------------------------------------------------------------
# backend.tf
# Remote state with S3 native locking. Placeholder bucket until a real account.
# State for BOTH regions lives in one file, because they are one system.
# -----------------------------------------------------------------------------
terraform {
  backend "s3" {
    bucket       = "REPLACE-ME-tfstate-bucket-app"
    key          = "app/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
