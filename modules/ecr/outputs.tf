# -----------------------------------------------------------------------------
# outputs.tf (ecr module)
# -----------------------------------------------------------------------------
output "repository_url" {
  description = "URL to push and pull images, e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com/webapp-prod/app."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the repository."
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Name of the repository."
  value       = aws_ecr_repository.this.name
}
