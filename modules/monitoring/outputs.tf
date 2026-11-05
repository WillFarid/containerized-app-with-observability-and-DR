# -----------------------------------------------------------------------------
# outputs.tf (monitoring module)
# -----------------------------------------------------------------------------
output "sns_topic_arn" {
  description = "ARN of the alerts topic. Other alarms (for example the DNS health check) publish here too."
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard."
  value       = aws_cloudwatch_dashboard.overview.dashboard_name
}

output "alarm_names" {
  description = "Names of the six alarms."
  value = [
    aws_cloudwatch_metric_alarm.target_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.unhealthy_hosts.alarm_name,
    aws_cloudwatch_metric_alarm.latency_p95.alarm_name,
    aws_cloudwatch_metric_alarm.cpu_high.alarm_name,
    aws_cloudwatch_metric_alarm.memory_high.alarm_name,
    aws_cloudwatch_metric_alarm.running_tasks_low.alarm_name,
  ]
}
