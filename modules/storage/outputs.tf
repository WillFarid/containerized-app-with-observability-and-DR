# -----------------------------------------------------------------------------
# outputs.tf (storage module)
# -----------------------------------------------------------------------------
output "source_bucket_name" {
  description = "Name of the primary bucket."
  value       = aws_s3_bucket.source.id
}

output "source_bucket_arn" {
  description = "ARN of the primary bucket."
  value       = aws_s3_bucket.source.arn
}

output "replica_bucket_name" {
  description = "Name of the replica bucket in the DR region."
  value       = aws_s3_bucket.replica.id
}

output "replica_bucket_arn" {
  description = "ARN of the replica bucket in the DR region."
  value       = aws_s3_bucket.replica.arn
}

output "source_kms_key_arn" {
  description = "ARN of the key that encrypts the primary bucket."
  value       = aws_kms_key.source.arn
}

output "replica_kms_key_arn" {
  description = "ARN of the key that encrypts the replica bucket."
  value       = aws_kms_key.replica.arn
}
