# -----------------------------------------------------------------------------
# main.tf (ecs-service module)
# Builds: cluster, two IAM roles, log group, task definition, app security
# group, and the Fargate service.
# -----------------------------------------------------------------------------

# =============================================================================
# Cluster
# =============================================================================
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"

  # Container Insights: per-service CPU, memory and network metrics.
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(var.tags, { Name = "${var.name}-cluster" })
}

# =============================================================================
# IAM: two roles, two different jobs
# =============================================================================
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# The EXECUTION role is used by ECS itself, BEFORE the app starts: pull the
# image, write logs (and, in the next step, fetch the secret).
resource "aws_iam_role" "execution" {
  name               = "${var.name}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = merge(var.tags, { Name = "${var.name}-ecs-execution-role" })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Permission to read EXACTLY ONE secret. The ARN pattern ends in six "?" because
# Secrets Manager appends a random 6-character suffix to every secret ARN. Six
# single-character wildcards match that suffix and nothing longer, so a secret
# named "<name>-v2" would NOT match.
data "aws_iam_policy_document" "read_secret" {
  statement {
    sid       = "ReadAppSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.secret_name}-??????"]
  }

  # Only when the secret uses our own key: permission to decrypt with that one key.
  dynamic "statement" {
    for_each = var.secret_kms_key_arn == null ? [] : [var.secret_kms_key_arn]

    content {
      sid       = "DecryptAppSecret"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "execution_read_secret" {
  name   = "read-app-secret"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.read_secret.json
}

# The TASK role is the identity of the RUNNING app. It has NO permissions, and
# this app needs none: the secret reaches it through the execution role at start
# time, and the app itself calls no AWS service. Anything the app might need
# later is granted here, one narrow statement at a time.
# Keeping it separate from the execution role means a compromised app cannot
# use the permissions ECS needs to pull images.
resource "aws_iam_role" "task" {
  name               = "${var.name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = merge(var.tags, { Name = "${var.name}-ecs-task-role" })
}

# =============================================================================
# Logs
# =============================================================================
resource "aws_cloudwatch_log_group" "app" {
  # checkov:skip=CKV_AWS_158: A KMS key policy needs the account ID, which cannot be looked up offline. Add a customer-managed key for a real deployment.
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, { Name = "${var.name}-app-logs" })
}

# =============================================================================
# Task definition: the blueprint for one copy of the app
# =============================================================================
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.name}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # each task gets its own network interface
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.image
      essential = true
      user      = "10001" # non-root, matches the Dockerfile

      # The container cannot write to its own filesystem. Anything an attacker
      # drops there would not persist, and the app does not need to write.
      readonlyRootFilesystem = true

      portMappings = [
        { containerPort = var.app_port, protocol = "tcp" }
      ]

      environment = [
        { name = "PORT", value = tostring(var.app_port) },
        { name = "APP_REGION", value = var.region },
      ]

      # ECS reads the secret when it STARTS the task and hands it to the
      # container as an environment variable. The value never appears in this
      # file, in Terraform state, or in the task definition. Only the NAME does.
      # A name works for a secret in the same region as the task.
      secrets = [
        { name = "APP_SECRET", valueFrom = var.secret_name }
      ]

      # ECS ignores the Dockerfile HEALTHCHECK, so it is defined here too.
      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:${var.app_port}/health')\" || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  tags = merge(var.tags, { Name = "${var.name}-app" })
}

# =============================================================================
# Security group: only the load balancer may reach the tasks
# =============================================================================
resource "aws_security_group" "app" {
  name        = "${var.name}-app-sg"
  description = "Fargate tasks: accept traffic only from the load balancer"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-app-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "App traffic from the load balancer"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = var.alb_sg_id
}

# Outbound HTTPS only: pulling the image, writing logs and reading the secret
# all go through the NAT gateway on port 443.
resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS out (image pull, logs, secrets) via NAT gateway"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# =============================================================================
# The service: keeps N healthy tasks running behind the load balancer
# =============================================================================
resource "aws_ecs_service" "app" {
  name             = "${var.name}-app"
  cluster          = aws_ecs_cluster.this.id
  task_definition  = aws_ecs_task_definition.app.arn
  desired_count    = var.desired_count
  launch_type      = "FARGATE"
  platform_version = "LATEST"
  propagate_tags   = "SERVICE"

  # Give a new task time to start before health checks can fail it.
  health_check_grace_period_seconds = 30

  # Rolling deployment that never drops below the current capacity.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # If a new version cannot become healthy, stop and roll back automatically.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  enable_execute_command = false # no shell into running containers

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "app"
    container_port   = var.app_port
  }

  tags = merge(var.tags, { Name = "${var.name}-app" })

  # Autoscaling (step 5) changes desired_count at runtime. Ignore it here so
  # `terraform apply` does not reset the scaler's decisions.
  lifecycle {
    ignore_changes = [desired_count]
  }
}

# =============================================================================
# Autoscaling: add tasks under load, remove them when it passes
# =============================================================================
# Application Auto Scaling changes the service's desired task count. That is why
# the service ignores desired_count above.
resource "aws_appautoscaling_target" "service" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.app.name}"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
}

# Target tracking: hold average CPU near the target. Scale OUT quickly (60 s)
# and scale IN slowly (300 s), so a short dip does not remove capacity just
# before the next burst.
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.service.service_namespace
  scalable_dimension = aws_appautoscaling_target.service.scalable_dimension
  resource_id        = aws_appautoscaling_target.service.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_percent
    scale_out_cooldown = 60
    scale_in_cooldown  = 300

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# A second signal: requests per task. CPU lags behind a sudden burst of traffic,
# while request count rises at once. With two policies, the one that wants more
# capacity wins.
resource "aws_appautoscaling_policy" "requests" {
  name               = "${var.name}-request-target-tracking"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.service.service_namespace
  scalable_dimension = aws_appautoscaling_target.service.scalable_dimension
  resource_id        = aws_appautoscaling_target.service.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.requests_per_target
    scale_out_cooldown = 60
    scale_in_cooldown  = 300

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = var.alb_request_label
    }
  }
}
