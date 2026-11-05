# -----------------------------------------------------------------------------
# main.tf (prod root module)
# Calls the child modules, once per region where needed.
# -----------------------------------------------------------------------------
locals {
  name = "${var.project}-${var.environment}" # e.g. webapp-prod

  # Carve /24 subnets out of each /16 with cidrsubnet(range, 8, N).
  # For 10.10.0.0/16 the numbers below give 10.10.0.0/24, 10.10.1.0/24, and so on.
  primary_public_cidrs   = [for n in [0, 1] : cidrsubnet(var.primary_vpc_cidr, 8, n)]
  primary_private_cidrs  = [for n in [10, 11] : cidrsubnet(var.primary_vpc_cidr, 8, n)]
  primary_database_cidrs = [for n in [20, 21] : cidrsubnet(var.primary_vpc_cidr, 8, n)]

  dr_public_cidrs   = [for n in [0, 1] : cidrsubnet(var.dr_vpc_cidr, 8, n)]
  dr_private_cidrs  = [for n in [10, 11] : cidrsubnet(var.dr_vpc_cidr, 8, n)]
  dr_database_cidrs = [for n in [20, 21] : cidrsubnet(var.dr_vpc_cidr, 8, n)]
}

# =============================================================================
# Network, primary region
# =============================================================================
# The same VPC module as the 3-tier project, reused as is. The database tier is
# not used by this app, so it stays empty. It costs nothing and keeps the layout
# identical to the module's tested design.
module "vpc_primary" {
  source = "../../modules/vpc"

  # IAM roles are GLOBAL, not per region. Two copies of one module in one
  # account must have different names, or the second copy would collide with
  # the first. The suffix keeps every name unique.
  name = "${local.name}-primary"

  vpc_cidr = var.primary_vpc_cidr
  azs      = var.primary_azs

  public_subnet_cidrs   = local.primary_public_cidrs
  private_subnet_cidrs  = local.primary_private_cidrs
  database_subnet_cidrs = local.primary_database_cidrs

  # Primary carries the real traffic: one NAT gateway per AZ, so losing an AZ
  # does not cut the other one off.
  single_nat_gateway = false
}

# =============================================================================
# Network, disaster recovery region
# =============================================================================
# The SAME module, pointed at the DR region with `providers`. Everything it
# creates (VPC, subnets, gateways) lands in dr_region.
module "vpc_dr" {
  source = "../../modules/vpc"

  providers = {
    aws = aws.dr
  }

  name = "${local.name}-dr"

  vpc_cidr = var.dr_vpc_cidr
  azs      = var.dr_azs

  public_subnet_cidrs   = local.dr_public_cidrs
  private_subnet_cidrs  = local.dr_private_cidrs
  database_subnet_cidrs = local.dr_database_cidrs

  # DR is a warm standby that carries little traffic until a failover, so one
  # shared NAT gateway saves roughly half the NAT cost. The trade-off: an AZ
  # failure in the DR region cuts the other AZ's outbound access. Accepted,
  # because DR is already the fallback.
  single_nat_gateway = true
}

# =============================================================================
# Image repositories (one per region) with cross-region replication
# =============================================================================
module "ecr_primary" {
  source = "../../modules/ecr"

  name            = "${local.name}-primary"
  repository_name = "${local.name}/app" # e.g. webapp-prod/app

  # Every image pushed here is copied to the DR region automatically.
  replication_region = var.dr_region
  account_id         = var.account_id
}

# The DR repository is created up front, so it is encrypted, scanned and
# immutable like the primary one, instead of being auto-created with defaults.
module "ecr_dr" {
  source = "../../modules/ecr"

  providers = {
    aws = aws.dr
  }

  name            = "${local.name}-dr"
  repository_name = "${local.name}/app" # same name: replication matches on it
  account_id      = var.account_id
}

# =============================================================================
# Secret (primary region) with a replica in the DR region
# =============================================================================
# The secret is created EMPTY. Its value is set out of band (see the secrets
# module), so no credential is ever written in code, in Git or in state.
module "secrets" {
  source = "../../modules/secrets"

  name        = local.name
  secret_name = "${local.name}/app-secret" # e.g. webapp-prod/app-secret

  replica_region = var.dr_region
}

# =============================================================================
# Primary region: load balancer and the Fargate service
# =============================================================================
module "alb_primary" {
  source = "../../modules/alb"

  name              = "${local.name}-primary"
  vpc_id            = module.vpc_primary.vpc_id
  public_subnet_ids = module.vpc_primary.public_subnet_ids

  app_port = 8080

  # PLACEHOLDER: a real ACM certificate (certificates are regional) is needed to
  # actually apply this.
  certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"

  # Must be globally unique in real life; change it if you ever deploy.
  access_logs_bucket_name = "webapp-prod-primary-alb-logs-replace-me"
}

module "app_primary" {
  source = "../../modules/ecs-service"

  name   = "${local.name}-primary"
  region = var.primary_region

  vpc_id             = module.vpc_primary.vpc_id
  private_subnet_ids = module.vpc_primary.private_subnet_ids

  alb_sg_id        = module.alb_primary.security_group_id
  target_group_arn = module.alb_primary.target_group_arn

  # The one secret this service may read, and the key that encrypts it.
  account_id         = var.account_id
  secret_name        = module.secrets.secret_name
  secret_kms_key_arn = module.secrets.kms_key_arn

  # Autoscaling: never below 2 tasks (one can fail without an outage), up to 6.
  min_capacity  = 2
  max_capacity  = 6
  desired_count = 2

  # Tells request-based scaling which load balancer and target group to watch.
  alb_request_label = "${module.alb_primary.alb_arn_suffix}/${module.alb_primary.target_group_arn_suffix}"

  # An explicit version tag, never "latest". The repository is immutable, so
  # 1.0.0 always means the same image.
  image    = "${module.ecr_primary.repository_url}:1.0.0"
  app_port = 8080

  # The target group must be attached to a listener before a service can
  # register tasks with it. Waiting for the whole load balancer module
  # guarantees that.
  depends_on = [module.alb_primary]
}

# The load balancer may send traffic to the tasks on the app port, and nowhere
# else. It lives here because it needs BOTH security groups to exist.
resource "aws_vpc_security_group_egress_rule" "alb_primary_to_app" {
  security_group_id            = module.alb_primary.security_group_id
  description                  = "Forward traffic to the app tasks"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = module.app_primary.security_group_id
}

# =============================================================================
# Observability (primary region): alarms, notifications and a dashboard
# =============================================================================
module "monitoring_primary" {
  source = "../../modules/monitoring"

  name       = "${local.name}-primary"
  region     = var.primary_region
  account_id = var.account_id

  # PLACEHOLDER: the recipient must confirm the subscription by email.
  alarm_email = "oncall@example.com"

  cluster_name            = module.app_primary.cluster_name
  service_name            = module.app_primary.service_name
  alb_arn_suffix          = module.alb_primary.alb_arn_suffix
  target_group_arn_suffix = module.alb_primary.target_group_arn_suffix

  min_running_tasks = 2
}

# =============================================================================
# Data: a bucket replicated to the DR region (this defines the 15-minute RPO)
# =============================================================================
module "storage" {
  source = "../../modules/storage"

  # One module, two regions: it creates the primary bucket with the default
  # provider and the replica bucket with the DR provider.
  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  name           = local.name
  source_region  = var.primary_region
  replica_region = var.dr_region

  # Must be globally unique in real life; change them if you ever deploy.
  source_bucket_name  = "webapp-prod-data-primary-replace-me"
  replica_bucket_name = "webapp-prod-data-dr-replace-me"

  # A replication slower than 15 minutes pages the same people as every other alarm.
  alarm_topic_arn = module.monitoring_primary.sns_topic_arn
}

# The running app gets exactly this much access to the bucket: read and write
# objects under app/, list only that prefix, and use the one key that encrypts
# them. It lives here because it connects two modules (the app and the bucket).
data "aws_iam_policy_document" "app_primary_data" {
  statement {
    sid       = "ReadWriteAppObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${module.storage.source_bucket_arn}/app/*"]
  }

  statement {
    sid       = "ListAppPrefixOnly"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [module.storage.source_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["app/*"]
    }
  }

  statement {
    sid       = "UseDataKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [module.storage.source_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "app_primary_data" {
  name   = "app-data-access"
  role   = module.app_primary.task_role_name
  policy = data.aws_iam_policy_document.app_primary_data.json
}

# =============================================================================
# Backup: point-in-time restore and long-term copies, in both regions
# =============================================================================
# Replication gives a fast failover but copies mistakes too. Backup keeps history.
module "backup" {
  source = "../../modules/backup"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  name          = local.name
  source_region = var.primary_region
  account_id    = var.account_id

  bucket_arn = module.storage.source_bucket_arn

  # The backup role may use exactly these two keys: the primary bucket's key to
  # read the data, and the replica's key for a restore in the DR region.
  bucket_kms_key_arns = [
    module.storage.source_kms_key_arn,
    module.storage.replica_kms_key_arn,
  ]

  # PLACEHOLDER: the recipient must confirm the subscription by email.
  alarm_email = "oncall@example.com"
}

# =============================================================================
# DISASTER RECOVERY REGION: a warm standby
#
# Warm standby = the full stack already runs in the DR region, scaled down to a
# minimum (1 task instead of 2). Compare:
#   pilot light   only data is kept, nothing runs   cheap, but slow to recover
#   warm standby  everything runs, small             a few minutes to recover
#   active-active everything runs at full size       fastest, and double the cost
# Warm standby is the option that can reasonably meet a 10-minute RTO.
#
# Everything below uses the SAME modules as the primary region, pointed at the
# DR region with `providers = { aws = aws.dr }`.
# =============================================================================
module "alb_dr" {
  source = "../../modules/alb"

  providers = {
    aws = aws.dr
  }

  name              = "${local.name}-dr"
  vpc_id            = module.vpc_dr.vpc_id
  public_subnet_ids = module.vpc_dr.public_subnet_ids

  app_port = 8080

  # PLACEHOLDER: ACM certificates are regional, so the DR region needs its own
  # certificate for the same domain name.
  certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"

  # Must be globally unique in real life; change it if you ever deploy.
  access_logs_bucket_name = "webapp-prod-dr-alb-logs-replace-me"
}

module "app_dr" {
  source = "../../modules/ecs-service"

  providers = {
    aws = aws.dr
  }

  name   = "${local.name}-dr"
  region = var.dr_region

  vpc_id             = module.vpc_dr.vpc_id
  private_subnet_ids = module.vpc_dr.private_subnet_ids

  alb_sg_id        = module.alb_dr.security_group_id
  target_group_arn = module.alb_dr.target_group_arn

  # The image is already here: ECR replication copied it from the primary region.
  image    = "${module.ecr_dr.repository_url}:1.0.0"
  app_port = 8080

  # The secret is already here too: the replica has the same name in this region.
  # It uses the AWS-managed key, so there is no customer key to grant.
  account_id         = var.account_id
  secret_name        = module.secrets.secret_name
  secret_kms_key_arn = null

  # Warm standby: ONE task now, and room to grow to 6 once traffic arrives.
  # The request-count policy reacts to the first burst of failed-over traffic.
  min_capacity  = 1
  max_capacity  = 6
  desired_count = 1

  alb_request_label = "${module.alb_dr.alb_arn_suffix}/${module.alb_dr.target_group_arn_suffix}"

  depends_on = [module.alb_dr]
}

# The DR load balancer may send traffic to the DR tasks on the app port only.
resource "aws_vpc_security_group_egress_rule" "alb_dr_to_app" {
  provider = aws.dr

  security_group_id            = module.alb_dr.security_group_id
  description                  = "Forward traffic to the app tasks"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = module.app_dr.security_group_id
}

# Alarms and a dashboard for the DR region too. The standby is only useful if
# someone notices that it is unhealthy BEFORE it is needed.
module "monitoring_dr" {
  source = "../../modules/monitoring"

  providers = {
    aws = aws.dr
  }

  name       = "${local.name}-dr"
  region     = var.dr_region
  account_id = var.account_id

  # PLACEHOLDER: the recipient must confirm the subscription by email.
  alarm_email = "oncall@example.com"

  cluster_name            = module.app_dr.cluster_name
  service_name            = module.app_dr.service_name
  alb_arn_suffix          = module.alb_dr.alb_arn_suffix
  target_group_arn_suffix = module.alb_dr.target_group_arn_suffix

  # The standby runs one task, so one is the minimum worth alarming on.
  min_running_tasks = 1
}

# After a failover the DR tasks work with the REPLICA bucket. The same narrow
# access as the primary: objects under app/, that one prefix, and the replica key.
# Note: writes made here are NOT copied back automatically. Returning to the
# primary region (failback) needs reverse replication. See the runbook.
data "aws_iam_policy_document" "app_dr_data" {
  statement {
    sid       = "ReadWriteAppObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${module.storage.replica_bucket_arn}/app/*"]
  }

  statement {
    sid       = "ListAppPrefixOnly"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [module.storage.replica_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["app/*"]
    }
  }

  statement {
    sid       = "UseDataKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [module.storage.replica_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "app_dr_data" {
  name   = "app-data-access"
  role   = module.app_dr.task_role_name
  policy = data.aws_iam_policy_document.app_dr_data.json
}

# =============================================================================
# Route 53: one name, and the health check decides which region answers
# =============================================================================
module "dns_failover" {
  source = "../../modules/dns-failover"

  name = local.name

  hosted_zone_id = var.hosted_zone_id
  domain_name    = var.app_domain_name

  primary_alb_dns_name   = module.alb_primary.alb_dns_name
  primary_alb_zone_id    = module.alb_primary.alb_zone_id
  secondary_alb_dns_name = module.alb_dr.alb_dns_name
  secondary_alb_zone_id  = module.alb_dr.alb_zone_id

  # Failover notifications go to the same people as every other alarm. The topic
  # is in us-east-1, where Route 53 health check metrics live.
  alarm_topic_arn = module.monitoring_primary.sns_topic_arn
}
