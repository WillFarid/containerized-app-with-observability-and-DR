# -----------------------------------------------------------------------------
# outputs.tf (secrets module)
# The secret VALUE is never output.
# -----------------------------------------------------------------------------
output "secret_name" {
  description = "Name of the secret. The ECS task definition references it by name."
  value       = aws_secretsmanager_secret.app.name
}

output "secret_arn" {
  description = "ARN of the secret."
  value       = aws_secretsmanager_secret.app.arn
}

output "kms_key_arn" {
  description = "ARN of the key that encrypts the secret. The task execution role needs decrypt rights on it."
  value       = aws_kms_key.secret.arn
}
