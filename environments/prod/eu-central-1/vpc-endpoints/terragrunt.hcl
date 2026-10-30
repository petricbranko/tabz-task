# ---------------------------------------------------------------------------------------------------------------------
# VPC endpoints (prod only) - official terraform-aws-modules/vpc//modules/vpc-endpoints
# Keeps AWS API traffic (secret injection, logs, ECS Exec, private ECR pulls) on the AWS network instead of the NAT
# gateways: lower NAT data-processing cost, and the platform keeps working if NAT/internet egress is impaired.
# Not in dev: interface endpoints are billed per AZ-hour, which costs more than dev's NAT traffic.
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl")).locals
}

terraform {
  source = "tfr:///terraform-aws-modules/vpc/aws//modules/vpc-endpoints?version=${local.common.module_versions.vpc}"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    vpc_id                  = "vpc-00000000000000000"
    vpc_cidr_block          = "10.20.0.0/16"
    private_subnets         = ["subnet-00000000000000011", "subnet-00000000000000012", "subnet-00000000000000013"]
    private_route_table_ids = ["rtb-00000000000000001", "rtb-00000000000000002", "rtb-00000000000000003"]
  }
}

inputs = {
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets

  create_security_group      = true
  security_group_name_prefix = "tabz-prod-vpce-"
  security_group_description = "HTTPS from inside the VPC to interface endpoints"
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from the VPC"
      cidr_blocks = [dependency.vpc.outputs.vpc_cidr_block]
    }
  }

  endpoints = {
    # Gateway endpoint: free; ECR image layers are served from S3.
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = dependency.vpc.outputs.private_route_table_ids
      tags            = { Name = "tabz-prod-s3" }
    }
    ecr_api        = { service = "ecr.api", private_dns_enabled = true, tags = { Name = "tabz-prod-ecr-api" } }
    ecr_dkr        = { service = "ecr.dkr", private_dns_enabled = true, tags = { Name = "tabz-prod-ecr-dkr" } }
    secretsmanager = { service = "secretsmanager", private_dns_enabled = true, tags = { Name = "tabz-prod-secretsmanager" } }
    logs           = { service = "logs", private_dns_enabled = true, tags = { Name = "tabz-prod-logs" } }
    kms            = { service = "kms", private_dns_enabled = true, tags = { Name = "tabz-prod-kms" } }
    ssmmessages    = { service = "ssmmessages", private_dns_enabled = true, tags = { Name = "tabz-prod-ssmmessages" } }
  }
}
