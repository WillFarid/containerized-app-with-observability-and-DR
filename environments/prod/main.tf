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

  # An explicit version tag, never "latest". The repository is immutable, so
  # 1.0.0 always means the same image.
  image    = "${module.ecr_primary.repository_url}:1.0.0"
  app_port = 8080

  desired_count = 2

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
