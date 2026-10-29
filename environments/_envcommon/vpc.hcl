# ---------------------------------------------------------------------------------------------------------------------
# VPC - official terraform-aws-modules/vpc
# Three subnet tiers per AZ:
#   public      /24  ALB + NAT gateways only
#   private     /20  ECS tasks (no public IPs). Large because every Fargate task consumes one ENI/IP
#   elasticache /24  Redis only, no route to the internet
# ---------------------------------------------------------------------------------------------------------------------

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl")).locals
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  region = read_terragrunt_config(find_in_parent_folders("region.hcl")).locals

  name = "${local.common.project}-${local.env.env}"
  cidr = local.env.vpc_cidr
  azs  = slice(local.region.azs, 0, local.env.az_count)
}

terraform {
  source = "tfr:///terraform-aws-modules/vpc/aws?version=${local.common.module_versions.vpc}"
}

inputs = {
  name = local.name
  cidr = local.cidr
  azs  = local.azs

  public_subnets      = [for i, _ in local.azs : cidrsubnet(local.cidr, 8, i)]       # x.x.0.0/24, x.x.1.0/24, ...
  private_subnets     = [for i, _ in local.azs : cidrsubnet(local.cidr, 4, i + 1)]   # x.x.16.0/20, x.x.32.0/20, ...
  elasticache_subnets = [for i, _ in local.azs : cidrsubnet(local.cidr, 8, i + 100)] # x.x.100.0/24, ...

  enable_dns_hostnames = true
  enable_dns_support   = true

  # NAT topology is decided per environment (single vs one-per-AZ).
  enable_nat_gateway = true

  create_elasticache_subnet_group = true
  # Own route table with only the local route. The module default reuses the private route tables, which would
  # give the data tier a NAT route to the internet.
  create_elasticache_subnet_route_table = true

  # Lock down the default SG / NACL so nothing can accidentally rely on them.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  public_subnet_tags      = { Tier = "public" }
  private_subnet_tags     = { Tier = "private" }
  elasticache_subnet_tags = { Tier = "data" }
}
