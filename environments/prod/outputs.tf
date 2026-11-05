# -----------------------------------------------------------------------------
# outputs.tf (prod root module)
# Nothing here is secret.
# -----------------------------------------------------------------------------
output "primary_vpc_id" {
  description = "ID of the VPC in the primary region."
  value       = module.vpc_primary.vpc_id
}

output "dr_vpc_id" {
  description = "ID of the VPC in the DR region."
  value       = module.vpc_dr.vpc_id
}

output "ecr_repository_url" {
  description = "Where to push the image. Replication copies it to the DR region."
  value       = module.ecr_primary.repository_url
}

output "primary_alb_dns_name" {
  description = "DNS name of the primary load balancer."
  value       = module.alb_primary.alb_dns_name
}

output "app_secret_name" {
  description = "Name of the app secret. Set its value out of band before the first deployment."
  value       = module.secrets.secret_name
}

output "primary_dashboard_name" {
  description = "Name of the CloudWatch dashboard for the primary region."
  value       = module.monitoring_primary.dashboard_name
}

output "primary_alarm_names" {
  description = "The six alarms for the primary region."
  value       = module.monitoring_primary.alarm_names
}
