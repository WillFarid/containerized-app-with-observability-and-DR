# -----------------------------------------------------------------------------
# main.tf (secrets module)
# An empty secret, its encryption key, and a replica in the DR region.
#
# NO SECRET VALUE IS WRITTEN HERE. A value in Terraform would end up in code,
# in Git or in state. This module creates the secret container only. The value
# is set out of band, once, by whoever owns the credential:
#
#   aws secretsmanager put-secret-value --secret-id <name> --secret-string '...'
#
# Do that BEFORE the ECS service starts, or tasks fail to launch.
# -----------------------------------------------------------------------------

resource "aws_kms_key" "secret" {
  # checkov:skip=CKV2_AWS_64: The AWS default key policy is used. An explicit policy needs the account ID written into a key policy, which this project keeps out of the code.
  description             = "${var.name} app secret encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 30 # safety net: a deleted key can be recovered for 30 days

  tags = merge(var.tags, { Name = "${var.name}-secret-key" })
}

resource "aws_kms_alias" "secret" {
  name          = "alias/${var.name}-secret"
  target_key_id = aws_kms_key.secret.key_id
}

resource "aws_secretsmanager_secret" "app" {
  # checkov:skip=CKV2_AWS_57: This is a static application credential set by its owner, not a database password. Automatic rotation needs a rotation function, which is a production step listed in the README.
  name                    = var.secret_name
  description             = "Application secret injected into the container as an environment variable"
  kms_key_id              = aws_kms_key.secret.arn
  recovery_window_in_days = var.recovery_window_in_days

  # Multi-region replication: the DR region gets its own read-only copy, kept in
  # sync automatically. Without it the standby service could not read the secret
  # during a failover. The replica uses the AWS-managed key of the DR region.
  dynamic "replica" {
    for_each = var.replica_region == null ? [] : [var.replica_region]

    content {
      region = replica.value
    }
  }

  tags = merge(var.tags, { Name = var.secret_name })
}
