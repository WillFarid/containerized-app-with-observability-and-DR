# -----------------------------------------------------------------------------
# outputs.tf (backup module)
# -----------------------------------------------------------------------------
output "primary_vault_name" {
  description = "Name of the vault in the primary region."
  value       = aws_backup_vault.primary.name
}

output "dr_vault_name" {
  description = "Name of the vault in the DR region."
  value       = aws_backup_vault.dr.name
}

output "backup_plan_id" {
  description = "ID of the backup plan."
  value       = aws_backup_plan.this.id
}

output "events_topic_arn" {
  description = "ARN of the topic that receives backup failure notifications."
  value       = aws_sns_topic.events.arn
}
