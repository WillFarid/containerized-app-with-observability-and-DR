# -----------------------------------------------------------------------------
# main.tf (backup module)
# Replication (the storage module) and backup solve DIFFERENT problems.
#
#   Replication  keeps a live copy in another region, within minutes. But it
#                copies EVERYTHING, including a bad write or a mistaken delete.
#   Backup       keeps history. You can restore to any moment in the last 35
#                days, from a copy in a second region, in vaults that cannot be
#                emptied by accident.
#
# You need both: replication for a fast failover, backup for "undo".
# -----------------------------------------------------------------------------

# =============================================================================
# Encryption keys for the vaults (one per region)
# =============================================================================
resource "aws_kms_key" "vault_primary" {
  # checkov:skip=CKV2_AWS_64: The AWS default key policy is used. An explicit policy needs the account ID written into a key policy, which this project keeps out of the code.
  description             = "${var.name} backup vault key (primary region)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = merge(var.tags, { Name = "${var.name}-backup-key-primary" })
}

resource "aws_kms_alias" "vault_primary" {
  name          = "alias/${var.name}-backup-vault"
  target_key_id = aws_kms_key.vault_primary.key_id
}

resource "aws_kms_key" "vault_dr" {
  # checkov:skip=CKV2_AWS_64: The AWS default key policy is used. An explicit policy needs the account ID written into a key policy, which this project keeps out of the code.
  provider = aws.dr

  description             = "${var.name} backup vault key (DR region)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = merge(var.tags, { Name = "${var.name}-backup-key-dr" })
}

resource "aws_kms_alias" "vault_dr" {
  provider = aws.dr

  name          = "alias/${var.name}-backup-vault"
  target_key_id = aws_kms_key.vault_dr.key_id
}

# =============================================================================
# Vaults: where recovery points are stored
# =============================================================================
resource "aws_backup_vault" "primary" {
  name        = "${var.name}-primary-vault"
  kms_key_arn = aws_kms_key.vault_primary.arn

  tags = merge(var.tags, { Name = "${var.name}-primary-vault" })
}

resource "aws_backup_vault" "dr" {
  provider = aws.dr

  name        = "${var.name}-dr-vault"
  kms_key_arn = aws_kms_key.vault_dr.arn

  tags = merge(var.tags, { Name = "${var.name}-dr-vault" })
}

# Vault Lock makes the vault write-once: nobody can delete a recovery point
# before its retention ends, and no backup can be given a shorter retention.
# That protects against a mistake, a malicious insider and ransomware.
#
# This is GOVERNANCE mode (changeable_for_days is not set), so a user with the
# right permission can still remove the lock. COMPLIANCE mode is irreversible
# after its cooling-off period, so it is a deliberate production decision and
# not something a lab should switch on.
resource "aws_backup_vault_lock_configuration" "primary" {
  backup_vault_name  = aws_backup_vault.primary.name
  min_retention_days = 7
  max_retention_days = 365
}

resource "aws_backup_vault_lock_configuration" "dr" {
  provider = aws.dr

  backup_vault_name  = aws_backup_vault.dr.name
  min_retention_days = 7
  max_retention_days = 365
}

# =============================================================================
# The role AWS Backup uses
# =============================================================================
data "aws_iam_policy_document" "backup_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${var.name}-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json

  tags = merge(var.tags, { Name = "${var.name}-backup-role" })
}

# AWS-managed policies: general backup and restore, plus the S3-specific pair.
resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
    "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup",
    "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore",
  ])

  role       = aws_iam_role.backup.name
  policy_arn = each.value
}

# The bucket is encrypted with our own keys, so the role also needs those keys,
# and only those keys, to read the data for a backup and write it on a restore.
data "aws_iam_policy_document" "backup_kms" {
  statement {
    sid    = "UseBucketKeys"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = var.bucket_kms_key_arns
  }
}

resource "aws_iam_role_policy" "backup_kms" {
  name   = "use-bucket-keys"
  role   = aws_iam_role.backup.id
  policy = data.aws_iam_policy_document.backup_kms.json
}

# =============================================================================
# The plan: what is backed up, how often, and for how long
# =============================================================================
resource "aws_backup_plan" "this" {
  name = "${var.name}-data-plan"

  # Rule 1: continuous backup = point-in-time restore. You can restore the
  # bucket to any second in the retention window, which is the answer to
  # "someone overwrote the wrong files at 14:32". A copy also goes to the DR vault.
  rule {
    rule_name                = "continuous-pitr"
    target_vault_name        = aws_backup_vault.primary.name
    schedule                 = "cron(0 5 * * ? *)" # 05:00 UTC daily
    enable_continuous_backup = true
    start_window             = 60
    completion_window        = 180

    lifecycle {
      delete_after = var.continuous_retention_days
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn

      lifecycle {
        delete_after = var.continuous_retention_days
      }
    }
  }

  # Rule 2: one backup a month, kept for a year, also copied to the DR region.
  # Long retention for audits and for problems noticed late.
  rule {
    rule_name         = "monthly-long-term"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 5 1 * ? *)" # 05:00 UTC on the 1st of the month
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = var.monthly_retention_days
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn

      lifecycle {
        delete_after = var.monthly_retention_days
      }
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-data-plan" })
}

resource "aws_backup_selection" "data_bucket" {
  name         = "${var.name}-data-bucket"
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = [var.bucket_arn]
}

# =============================================================================
# Failure notifications: a backup nobody knows failed is not a backup
# =============================================================================
# AWS Backup publishes to the topic itself, so the topic needs its own key whose
# policy lets the Backup service use it, only through SNS. To VERIFY in a real
# account: force a failed job and check that the email arrives.
resource "aws_kms_key" "events" {
  description             = "${var.name} backup events topic encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableAccountAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowBackupThroughSnsOnly"
        Effect    = "Allow"
        Principal = { Service = "backup.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "sns.${var.source_region}.amazonaws.com"
          }
        }
      },
    ]
  })

  tags = merge(var.tags, { Name = "${var.name}-backup-events-key" })
}

resource "aws_kms_alias" "events" {
  name          = "alias/${var.name}-backup-events"
  target_key_id = aws_kms_key.events.key_id
}

resource "aws_sns_topic" "events" {
  name              = "${var.name}-backup-events"
  kms_master_key_id = aws_kms_key.events.id

  tags = merge(var.tags, { Name = "${var.name}-backup-events" })
}

# Only the Backup service, acting for THIS account, may publish to the topic.
data "aws_iam_policy_document" "events_topic" {
  statement {
    sid       = "AllowBackupToPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.events.arn]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [var.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "events" {
  arn    = aws_sns_topic.events.arn
  policy = data.aws_iam_policy_document.events_topic.json
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.events.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_backup_vault_notifications" "primary" {
  backup_vault_name = aws_backup_vault.primary.name
  sns_topic_arn     = aws_sns_topic.events.arn

  backup_vault_events = [
    "BACKUP_JOB_FAILED",
    "COPY_JOB_FAILED",
    "S3_BACKUP_OBJECT_FAILED",
  ]

  depends_on = [aws_sns_topic_policy.events]
}
