# -----------------------------------------------------------------------------
# main.tf (ecr module)
# A private image repository: encrypted, scanned, tags that cannot be
# overwritten, old images cleaned up, and (optionally) copied to another
# region so the disaster recovery site can pull the same image.
# -----------------------------------------------------------------------------

# Encryption key (customer-managed, rotated yearly).
resource "aws_kms_key" "ecr" {
  # checkov:skip=CKV2_AWS_64: The AWS default key policy is used. An explicit policy needs the account ID written into a key policy, which this project keeps out of the code.
  description             = "${var.name} ECR encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 30 # safety net: a deleted key can be recovered for 30 days

  tags = merge(var.tags, { Name = "${var.name}-ecr-key" })
}

resource "aws_kms_alias" "ecr" {
  name          = "alias/${var.name}-ecr"
  target_key_id = aws_kms_key.ecr.key_id
}

resource "aws_ecr_repository" "this" {
  name = var.repository_name

  # IMMUTABLE: a tag such as 1.0.0 can never be pointed at a different image.
  # What is deployed is exactly what was scanned and approved.
  image_tag_mutability = "IMMUTABLE"

  # Scan every pushed image for known vulnerabilities.
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  tags = merge(var.tags, { Name = var.repository_name })
}

# Keep storage (and cost) in check: drop untagged images after two weeks, and
# keep only the 10 most recent images overall.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the 10 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}

# Cross-region replication: every image pushed to this repository is copied to
# the DR region automatically. Without it the standby service could not pull
# its image during a failover. This is a registry-wide setting, so it is
# created only where replication_region is set.
resource "aws_ecr_replication_configuration" "this" {
  count = var.replication_region == null ? 0 : 1

  replication_configuration {
    rule {
      destination {
        region      = var.replication_region
        registry_id = var.account_id
      }

      repository_filter {
        filter      = var.repository_name
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}
