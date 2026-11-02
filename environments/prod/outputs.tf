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
