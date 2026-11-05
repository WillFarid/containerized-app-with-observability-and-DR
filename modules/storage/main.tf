# -----------------------------------------------------------------------------
# main.tf (storage module)
# A data bucket in the primary region, continuously copied to a second bucket in
# the disaster recovery region. This is what defines the RPO.
#
#   RPO (recovery point objective) = how much data you can afford to lose.
#   S3 Replication Time Control (RTC) replicates 99.99 percent of objects within
#   15 minutes and publishes a metric to prove it, so the target RPO is 15 minutes.
#   That is a target backed by an AWS SLA and an alarm. It is not a measurement.
#
# Both buckets are encrypted with their own regional customer-managed key,
# versioned (replication requires it), private, and HTTPS-only.
# -----------------------------------------------------------------------------

locals {
  replication_rule_id = "replicate-all-to-dr"
}

# =============================================================================
# Encryption keys: one per region (a key never leaves its region)
# =============================================================================
resource "aws_kms_key" "source" {
  # checkov:skip=CKV2_AWS_64: The AWS default key policy is used. An explicit policy needs the account ID written into a key policy, which this project keeps out of the code.
  description             = "${var.name} data bucket key (primary region)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = merge(var.tags, { Name = "${var.name}-data-key-primary" })
}

resource "aws_kms_alias" "source" {
  name          = "alias/${var.name}-data"
  target_key_id = aws_kms_key.source.key_id
}

resource "aws_kms_key" "replica" {
  # checkov:skip=CKV2_AWS_64: The AWS default key policy is used. An explicit policy needs the account ID written into a key policy, which this project keeps out of the code.
  provider = aws.dr

  description             = "${var.name} data bucket key (DR region)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = merge(var.tags, { Name = "${var.name}-data-key-dr" })
}

resource "aws_kms_alias" "replica" {
  provider = aws.dr

  name          = "alias/${var.name}-data"
  target_key_id = aws_kms_key.replica.key_id
}

# =============================================================================
# Primary bucket
# =============================================================================
resource "aws_s3_bucket" "source" {
  # checkov:skip=CKV_AWS_18: Server access logging to a central log bucket is a production addition listed in the README.
  # checkov:skip=CKV2_AWS_62: Event notifications are not needed for this bucket.
  bucket        = var.source_bucket_name
  force_destroy = var.force_destroy

  tags = merge(var.tags, { Name = var.source_bucket_name })
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning is REQUIRED on both sides of replication. It also means an
# overwritten or deleted object can be recovered.
resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.source.arn
    }

    # One bucket-level key request instead of one per object: far fewer KMS
    # calls, so lower cost and no throttling at volume.
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    id     = "clean-up-old-versions"
    status = "Enabled"

    filter {}

    # Current objects are never expired. Only superseded versions are removed.
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.source]
}

data "aws_iam_policy_document" "source_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.source.arn, "${aws_s3_bucket.source.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "source" {
  bucket = aws_s3_bucket.source.id
  policy = data.aws_iam_policy_document.source_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.source]
}

# =============================================================================
# Replica bucket (DR region)
# =============================================================================
resource "aws_s3_bucket" "replica" {
  # checkov:skip=CKV_AWS_144: This is the replication TARGET. Replication runs from the primary bucket to this one.
  # checkov:skip=CKV_AWS_18: Server access logging to a central log bucket is a production addition listed in the README.
  # checkov:skip=CKV2_AWS_62: Event notifications are not needed for this bucket.
  provider = aws.dr

  bucket        = var.replica_bucket_name
  force_destroy = var.force_destroy

  tags = merge(var.tags, { Name = var.replica_bucket_name })
}

resource "aws_s3_bucket_public_access_block" "replica" {
  provider = aws.dr

  bucket = aws_s3_bucket.replica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "replica" {
  provider = aws.dr

  bucket = aws_s3_bucket.replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "replica" {
  provider = aws.dr

  bucket = aws_s3_bucket.replica.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.replica.arn
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "replica" {
  provider = aws.dr

  bucket = aws_s3_bucket.replica.id

  rule {
    id     = "clean-up-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.replica]
}

data "aws_iam_policy_document" "replica_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.replica.arn, "${aws_s3_bucket.replica.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "replica" {
  provider = aws.dr

  bucket = aws_s3_bucket.replica.id
  policy = data.aws_iam_policy_document.replica_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.replica]
}

# =============================================================================
# Replication: the role S3 uses, and the rule itself
# =============================================================================
data "aws_iam_policy_document" "replication_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  name               = "${var.name}-s3-replication-role"
  assume_role_policy = data.aws_iam_policy_document.replication_assume.json

  tags = merge(var.tags, { Name = "${var.name}-s3-replication-role" })
}

# Least privilege: read from the source bucket, write to the replica bucket,
# decrypt with the source key and encrypt with the replica key. The KMS
# conditions limit each key to S3 acting on that one bucket's objects.
data "aws_iam_policy_document" "replication" {
  statement {
    sid       = "ReadReplicationSettings"
    effect    = "Allow"
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [aws_s3_bucket.source.arn]
  }

  statement {
    sid    = "ReadSourceObjectVersions"
    effect = "Allow"
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.source.arn}/*"]
  }

  statement {
    sid       = "WriteReplicas"
    effect    = "Allow"
    actions   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
    resources = ["${aws_s3_bucket.replica.arn}/*"]
  }

  statement {
    sid       = "DecryptWithSourceKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.source.arn]

    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values   = ["s3.${var.source_region}.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = ["${aws_s3_bucket.source.arn}/*"]
    }
  }

  statement {
    sid       = "EncryptWithReplicaKey"
    effect    = "Allow"
    actions   = ["kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.replica.arn]

    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values   = ["s3.${var.replica_region}.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = ["${aws_s3_bucket.replica.arn}/*"]
    }
  }
}

resource "aws_iam_role_policy" "replication" {
  name   = "replicate-to-dr"
  role   = aws_iam_role.replication.id
  policy = data.aws_iam_policy_document.replication.json
}

resource "aws_s3_bucket_replication_configuration" "this" {
  bucket = aws_s3_bucket.source.id
  role   = aws_iam_role.replication.arn

  rule {
    id       = local.replication_rule_id
    status   = "Enabled"
    priority = 1

    filter {}

    # Deletes are copied too, as delete markers. Because both buckets are
    # versioned, a deleted object can still be restored in either region.
    delete_marker_replication {
      status = "Enabled"
    }

    # The source objects are KMS-encrypted, so replication must be told to
    # handle them.
    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.replica.arn
      storage_class = "STANDARD"

      # Re-encrypt every replica with the DR region's own key.
      encryption_configuration {
        replica_kms_key_id = aws_kms_key.replica.arn
      }

      # Replication Time Control: the 15-minute commitment. It costs extra per
      # GB, and requires the metrics block below.
      replication_time {
        status = "Enabled"

        time {
          minutes = 15
        }
      }

      # Publishes ReplicationLatency, which the alarm below watches.
      metrics {
        status = "Enabled"

        event_threshold {
          minutes = 15
        }
      }
    }
  }

  # Both buckets must be versioned before the rule can be created.
  depends_on = [
    aws_s3_bucket_versioning.source,
    aws_s3_bucket_versioning.replica,
  ]
}

# =============================================================================
# The alarm that watches the RPO
# =============================================================================
# If the slowest replication in a 5-minute window takes more than 900 seconds
# (15 minutes), the RPO target is being missed and someone is told.
resource "aws_cloudwatch_metric_alarm" "replication_latency" {
  alarm_name          = "${var.name}-replication-latency"
  alarm_description   = "Replication to the DR region is slower than the 15-minute target. This is the RPO."
  namespace           = "AWS/S3"
  metric_name         = "ReplicationLatency"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 900
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching" # no new objects means nothing is behind

  dimensions = {
    SourceBucket      = aws_s3_bucket.source.id
    DestinationBucket = aws_s3_bucket.replica.id
    RuleId            = local.replication_rule_id
  }

  alarm_actions = [var.alarm_topic_arn]
  ok_actions    = [var.alarm_topic_arn]

  tags = merge(var.tags, { Name = "${var.name}-replication-latency" })
}
