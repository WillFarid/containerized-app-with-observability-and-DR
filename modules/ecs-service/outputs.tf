# -----------------------------------------------------------------------------
# outputs.tf (ecs-service module)
# -----------------------------------------------------------------------------
output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "Name of the ECS service (used by autoscaling and monitoring)."
  value       = aws_ecs_service.app.name
}

output "security_group_id" {
  description = "Security group of the tasks."
  value       = aws_security_group.app.id
}

output "task_role_name" {
  description = "Name of the app's runtime role. Later steps attach narrow permissions to it."
  value       = aws_iam_role.task.name
}

output "execution_role_name" {
  description = "Name of the role ECS uses to start tasks."
  value       = aws_iam_role.execution.name
}

output "log_group_name" {
  description = "Name of the container log group."
  value       = aws_cloudwatch_log_group.app.name
}
