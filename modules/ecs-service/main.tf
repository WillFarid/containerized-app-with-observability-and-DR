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

# The TASK role is the identity of the RUNNING app. It starts with NO
# permissions. Later steps grant exactly what the app needs and nothing more.
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
