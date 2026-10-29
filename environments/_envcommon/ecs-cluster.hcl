# ---------------------------------------------------------------------------------------------------------------------
# ECS cluster - official terraform-aws-modules/ecs//modules/cluster
# Fargate-only cluster. Capacity provider strategy is set per service; the cluster default is a safe fallback.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl")).locals
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals

  name = "${local.common.project}-${local.env.env}"
}

terraform {
  source = "tfr:///terraform-aws-modules/ecs/aws//modules/cluster?version=${local.common.module_versions.ecs}"
}

inputs = {
  name = local.name

  cluster_capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy = {
    FARGATE = {
      weight = 1
      base   = 0
    }
  }

  # ECS Exec sessions are audited to the cluster log group created by the module.
  create_cloudwatch_log_group = true
}
