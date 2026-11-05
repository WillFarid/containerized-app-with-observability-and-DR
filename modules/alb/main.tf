# -----------------------------------------------------------------------------
# main.tf (alb module)
# Builds: access-log bucket, security group, ALB, target group, listeners.
#
# Differences from the EC2 version of this module (3-tier project):
#   * the target group type is "ip", because Fargate tasks register by address
#   * the security group lives here, and its outbound rule is added by the root
#     module, once the app's security group exists (avoids a circular reference)
# -----------------------------------------------------------------------------

# =============================================================================
# Access logs bucket
# =============================================================================
resource "aws_s3_bucket" "alb_logs" {
  # checkov:skip=CKV_AWS_145: ALB access log delivery supports SSE-S3 only, not KMS keys
  # checkov:skip=CKV_AWS_144: Cross-region replication is not justified for disposable access logs
  # checkov:skip=CKV_AWS_18: This bucket is itself the logging destination
  # checkov:skip=CKV2_AWS_62: Event notifications are not needed for a log archive
  bucket        = var.access_logs_bucket_name
  force_destroy = var.logs_force_destroy

  tags = merge(var.tags, { Name = var.access_logs_bucket_name })
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.access_logs_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.alb_logs]
}

# The AWS-owned account that delivers ALB logs in this region (a built-in lookup
# table, not an API call, so it is safe offline).
data "aws_elb_service_account" "alb_logs" {}

data "aws_iam_policy_document" "alb_logs" {
  statement {
    sid       = "AllowELBLogDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs.arn}/alb/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.alb_logs.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.alb_logs.arn, "${aws_s3_bucket.alb_logs.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = data.aws_iam_policy_document.alb_logs.json

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}

# =============================================================================
# Security group: the internet may reach the load balancer, nothing else may
# =============================================================================
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "Load balancer: accepts web traffic from the internet"
  vpc_id      = var.vpc_id

  # No outbound rule here on purpose. The root module adds exactly one: to the
  # app's security group on the app port.

  tags = merge(var.tags, { Name = "${var.name}-alb-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  # checkov:skip=CKV_AWS_260: Port 80 only serves a 301 redirect to HTTPS, no content is served over HTTP
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet (redirected to HTTPS)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# =============================================================================
# The load balancer
# =============================================================================
resource "aws_lb" "this" {
  # checkov:skip=CKV2_AWS_28: AWS WAF is a production hardening step listed in the README, not part of this baseline
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = var.enable_deletion_protection

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  tags = merge(var.tags, { Name = "${var.name}-alb" })

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

# Target group: where the load balancer sends traffic.
# target_type "ip": Fargate tasks have their own network interface and address,
# and the service registers each one here.
resource "aws_lb_target_group" "app" {
  name        = "${var.name}-app-tg"
  port        = var.app_port
  protocol    = "HTTP" # TLS ends at the load balancer; traffic inside the VPC is HTTP
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, { Name = "${var.name}-app-tg" })
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = merge(var.tags, { Name = "${var.name}-https-listener" })
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-http-redirect" })
}
