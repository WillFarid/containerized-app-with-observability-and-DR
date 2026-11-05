# -----------------------------------------------------------------------------
# main.tf (dns-failover module)
# One name, two load balancers, and Route 53 decides which one answers.
#
#   app.example.com  -->  PRIMARY load balancer   while its health check passes
#                    -->  SECONDARY (DR) load balancer   when it does not
#
# HOW LONG DOES A FAILOVER TAKE? (the RTO, a TARGET and not a measurement)
#   detect the failure   health check every 30 s, 3 failures in a row  = up to 90 s
#   DNS cache expires    alias records on a load balancer use a 60 s TTL = up to 60 s
#   DR service answers   the standby already runs, so it serves at once
#   full capacity        autoscaling adds tasks, roughly 2 to 5 minutes
#   Total: traffic moves in about 3 minutes, full capacity in about 8.
#   The 10-minute RTO target leaves margin on top of that.
# -----------------------------------------------------------------------------

# =============================================================================
# The health check: Route 53 asks the primary "are you OK?" from many places
# =============================================================================
resource "aws_route53_health_check" "primary" {
  type              = "HTTPS"
  fqdn              = var.primary_alb_dns_name
  port              = 443
  resource_path     = var.health_check_path
  request_interval  = 30 # seconds between checks
  failure_threshold = 3  # consecutive failures before it is declared unhealthy
  enable_sni        = true

  tags = merge(var.tags, { Name = "${var.name}-primary-health" })
}

# =============================================================================
# Failover records: same name, two answers, one active at a time
# =============================================================================
resource "aws_route53_record" "primary" {
  zone_id        = var.hosted_zone_id
  name           = var.domain_name
  type           = "A"
  set_identifier = "primary"

  failover_routing_policy {
    type = "PRIMARY"
  }

  # An alias record points at a load balancer instead of an IP address.
  alias {
    name                   = var.primary_alb_dns_name
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }

  health_check_id = aws_route53_health_check.primary.id
}

resource "aws_route53_record" "secondary" {
  zone_id        = var.hosted_zone_id
  name           = var.domain_name
  type           = "A"
  set_identifier = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.secondary_alb_dns_name
    zone_id                = var.secondary_alb_zone_id
    evaluate_target_health = true
  }
}

# =============================================================================
# Tell a human when a failover happens
# =============================================================================
# Route 53 health check metrics exist ONLY in us-east-1, so this alarm must be
# created there. That is the primary region in this project, which uses the
# default provider. If the primary region ever changes, this alarm must stay in
# us-east-1. Missing data counts as a problem: a health check that stops
# reporting should never look healthy.
resource "aws_cloudwatch_metric_alarm" "primary_unhealthy" {
  alarm_name          = "${var.name}-primary-unhealthy"
  alarm_description   = "Route 53 considers the primary region unhealthy. Traffic is failing over to the DR region."
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  dimensions          = { HealthCheckId = aws_route53_health_check.primary.id }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [var.alarm_topic_arn]
  ok_actions    = [var.alarm_topic_arn]

  tags = merge(var.tags, { Name = "${var.name}-primary-unhealthy" })
}
