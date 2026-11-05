# -----------------------------------------------------------------------------
# outputs.tf (dns-failover module)
# -----------------------------------------------------------------------------
output "health_check_id" {
  description = "ID of the Route 53 health check on the primary load balancer."
  value       = aws_route53_health_check.primary.id
}

output "fqdn" {
  description = "The name users type."
  value       = aws_route53_record.primary.fqdn
}
