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
