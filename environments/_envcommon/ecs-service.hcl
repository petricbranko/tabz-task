# ---------------------------------------------------------------------------------------------------------------------
# ECS service - modules/ecs-service
# Wires a service unit to the shared platform units (VPC, cluster, ALB). Service-specific settings (image, sizing)
# live in environments/<env>/<region>/services/<service>/terragrunt.hcl.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  common     = read_terragrunt_config(find_in_parent_folders("common.hcl")).locals
  env        = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  region_dir = dirname(find_in_parent_folders("region.hcl"))

  service      = basename(get_terragrunt_dir())
  name         = "${local.common.project}-${local.env.env}-${local.service}"
  listener_key = local.env.certificate_arn != "" ? "https" : "http"
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../modules//ecs-service"
}

dependency "vpc" {
  config_path = "${local.region_dir}/vpc"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    vpc_id          = "vpc-00000000000000000"
    private_subnets = ["subnet-00000000000000011", "subnet-00000000000000012", "subnet-00000000000000013"]
  }
}

dependency "ecs_cluster" {
  config_path = "${local.region_dir}/ecs-cluster"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    arn = "arn:aws:ecs:eu-central-1:111111111111:cluster/mock"
  }
}

dependency "alb" {
  config_path = "${local.region_dir}/alb"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    security_group_id = "sg-00000000000000001"
    listeners = {
      http  = { arn = "arn:aws:elasticloadbalancing:eu-central-1:111111111111:listener/app/mock/0000000000000000/0000000000000001" }
      https = { arn = "arn:aws:elasticloadbalancing:eu-central-1:111111111111:listener/app/mock/0000000000000000/0000000000000002" }
    }
  }
}

inputs = {
  name        = local.name
  cluster_arn = dependency.ecs_cluster.outputs.arn
  vpc_id      = dependency.vpc.outputs.vpc_id
  subnet_ids  = dependency.vpc.outputs.private_subnets

  load_balancer = {
    listener_arn      = dependency.alb.outputs.listeners[local.listener_key].arn
    security_group_id = dependency.alb.outputs.security_group_id
    priority          = 100
  }
}
