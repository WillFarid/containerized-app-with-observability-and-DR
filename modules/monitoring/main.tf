# -----------------------------------------------------------------------------
# main.tf (monitoring module)
# One place that answers "is the service healthy, and who finds out if not?":
#   * an encrypted SNS topic that carries notifications
#   * six alarms, each chosen because it tells you something the others cannot
#   * a dashboard with the same signals
#
# The six, by question:
#   Is the app erroring?       target 5xx count
#   Are the tasks healthy?     unhealthy host count
#   Is it slow?                p95 response time
#   Is it running out of CPU?  CPU utilization
#   ...or memory?              memory utilization
#   Is capacity missing?       running task count below the minimum
# -----------------------------------------------------------------------------

locals {
  alb_dimensions = { LoadBalancer = var.alb_arn_suffix }
  tg_dimensions  = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
  svc_dimensions = { ClusterName = var.cluster_name, ServiceName = var.service_name }
}

# =============================================================================
# Notifications: encrypted topic
# =============================================================================
# CloudWatch alarms cannot publish to a topic encrypted with the AWS-managed
# key, so the topic uses our own key, and the key policy lets the CloudWatch
# service use it. The condition limits that to alarms in THIS account and region.
# To VERIFY in a real account: send a test alarm and confirm the email arrives.
resource "aws_kms_key" "alerts" {
  description             = "${var.name} alerts topic encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableAccountAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchAlarmsToPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:cloudwatch:${var.region}:${var.account_id}:alarm:*"
          }
        }
      },
    ]
  })

  tags = merge(var.tags, { Name = "${var.name}-alerts-key" })
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/${var.name}-alerts"
  target_key_id = aws_kms_key.alerts.key_id
}

resource "aws_sns_topic" "alerts" {
  name              = "${var.name}-alerts"
  kms_master_key_id = aws_kms_key.alerts.id

  tags = merge(var.tags, { Name = "${var.name}-alerts" })
}

# An email subscription stays "pending" until the recipient clicks the
# confirmation link, so a real deployment needs a person to do that once.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# =============================================================================
# The six alarms
# =============================================================================

# 1. Is the app erroring? Server errors returned by the TASKS (not the load
#    balancer). 3 of the last 5 minutes with 5 or more errors.
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.name}-target-5xx"
  alarm_description   = "The app is returning server errors (HTTP 5xx)."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = local.alb_dimensions
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching" # no traffic means no errors

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(var.tags, { Name = "${var.name}-target-5xx" })
}

# 2. Are the tasks healthy? Any task failing the load balancer's health check
#    for two minutes in a row. This is also the signal behind a failover.
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.name}-unhealthy-hosts"
  alarm_description   = "At least one task is failing its health check."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = local.tg_dimensions
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(var.tags, { Name = "${var.name}-unhealthy-hosts" })
}

# 3. Is it slow? The 95th percentile, because the average hides the slowest
#    5% of requests, which are the ones users complain about.
resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name          = "${var.name}-latency-p95"
  alarm_description   = "95th percentile response time is above 1 second."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = local.alb_dimensions
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(var.tags, { Name = "${var.name}-latency-p95" })
}

# 4. Is it running out of CPU? Autoscaling aims for 60 percent, so 85 percent
#    for five minutes means scaling is not keeping up (or is at its maximum).
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name}-cpu-high"
  alarm_description   = "Average CPU has been above 85% for 5 minutes. Autoscaling is not keeping up."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = local.svc_dimensions
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(var.tags, { Name = "${var.name}-cpu-high" })
}

# 5. ...or memory? Memory is not scaled on, so this is the early warning for a
#    leak or an undersized task before tasks are killed for running out of it.
resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "${var.name}-memory-high"
  alarm_description   = "Average memory has been above 85% for 5 minutes."
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  dimensions          = local.svc_dimensions
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(var.tags, { Name = "${var.name}-memory-high" })
}

# 6. Is capacity missing? Fewer tasks running than the minimum. "No data" counts
#    as a problem here, because a service that should be running and reports
#    nothing is a service that is down. Uses Container Insights metrics.
resource "aws_cloudwatch_metric_alarm" "running_tasks_low" {
  alarm_name          = "${var.name}-running-tasks-low"
  alarm_description   = "Fewer tasks are running than the minimum of ${var.min_running_tasks}."
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  dimensions          = local.svc_dimensions
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = var.min_running_tasks
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(var.tags, { Name = "${var.name}-running-tasks-low" })
}

# =============================================================================
# Dashboard: the same signals on one page
# =============================================================================
resource "aws_cloudwatch_dashboard" "overview" {
  dashboard_name = "${var.name}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "alarm"
        x      = 0
        y      = 0
        width  = 24
        height = 3
        properties = {
          title = "Alarm status"
          alarms = [
            aws_cloudwatch_metric_alarm.target_5xx.arn,
            aws_cloudwatch_metric_alarm.unhealthy_hosts.arn,
            aws_cloudwatch_metric_alarm.latency_p95.arn,
            aws_cloudwatch_metric_alarm.cpu_high.arn,
            aws_cloudwatch_metric_alarm.memory_high.arn,
            aws_cloudwatch_metric_alarm.running_tasks_low.arn,
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 3
        width  = 12
        height = 6
        properties = {
          title  = "Requests and server errors"
          region = var.region
          period = 60
          metrics = [
            concat(["AWS/ApplicationELB", "RequestCount"], flatten([for k, v in local.alb_dimensions : [k, v]]), [{ stat = "Sum" }]),
            concat(["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count"], flatten([for k, v in local.alb_dimensions : [k, v]]), [{ stat = "Sum" }]),
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 3
        width  = 12
        height = 6
        properties = {
          title  = "Response time (p95)"
          region = var.region
          period = 60
          metrics = [
            concat(["AWS/ApplicationELB", "TargetResponseTime"], flatten([for k, v in local.alb_dimensions : [k, v]]), [{ stat = "p95" }]),
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 9
        width  = 12
        height = 6
        properties = {
          title  = "Healthy and unhealthy tasks"
          region = var.region
          period = 60
          metrics = [
            concat(["AWS/ApplicationELB", "HealthyHostCount"], flatten([for k, v in local.tg_dimensions : [k, v]]), [{ stat = "Minimum" }]),
            concat(["AWS/ApplicationELB", "UnHealthyHostCount"], flatten([for k, v in local.tg_dimensions : [k, v]]), [{ stat = "Maximum" }]),
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 9
        width  = 12
        height = 6
        properties = {
          title  = "CPU and memory utilization"
          region = var.region
          period = 60
          metrics = [
            concat(["AWS/ECS", "CPUUtilization"], flatten([for k, v in local.svc_dimensions : [k, v]]), [{ stat = "Average" }]),
            concat(["AWS/ECS", "MemoryUtilization"], flatten([for k, v in local.svc_dimensions : [k, v]]), [{ stat = "Average" }]),
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 15
        width  = 24
        height = 6
        properties = {
          title  = "Running and desired tasks"
          region = var.region
          period = 60
          metrics = [
            concat(["ECS/ContainerInsights", "RunningTaskCount"], flatten([for k, v in local.svc_dimensions : [k, v]]), [{ stat = "Minimum" }]),
            concat(["ECS/ContainerInsights", "DesiredTaskCount"], flatten([for k, v in local.svc_dimensions : [k, v]]), [{ stat = "Maximum" }]),
          ]
        }
      },
    ]
  })
}
