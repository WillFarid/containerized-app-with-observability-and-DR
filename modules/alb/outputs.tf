# -----------------------------------------------------------------------------
# outputs.tf (alb module)
# -----------------------------------------------------------------------------
output "alb_arn" {
  description = "ARN of the load balancer."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the load balancer (Route 53 points at this)."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Route 53 hosted zone ID of the load balancer (needed for alias records)."
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "Security group of the load balancer."
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "Target group ARN. The ECS service registers its tasks here."
  value       = aws_lb_target_group.app.arn
}

output "alb_arn_suffix" {
  description = "Load balancer ARN suffix, used by CloudWatch alarm dimensions."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix, used by CloudWatch alarm dimensions."
  value       = aws_lb_target_group.app.arn_suffix
}

output "access_logs_bucket" {
  description = "Name of the S3 bucket holding access logs."
  value       = aws_s3_bucket.alb_logs.id
}
