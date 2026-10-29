# ---------------------------------------------------------------------------------------------------------------------
# Redis (ElastiCache replication group) + the application secret - modules/redis
# ---------------------------------------------------------------------------------------------------------------------

locals {
  common     = read_terragrunt_config(find_in_parent_folders("common.hcl")).locals
  env        = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  region_dir = dirname(find_in_parent_folders("region.hcl"))

  name = "${local.common.project}-${local.env.env}"
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../modules//redis"
}

dependency "vpc" {
  config_path = "${local.region_dir}/vpc"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    vpc_id                        = "vpc-00000000000000000"
    elasticache_subnet_group_name = "mock-elasticache-subnet-group"
  }
}

dependency "kms" {
  config_path = "${local.region_dir}/kms"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    key_arn = "arn:aws:kms:eu-central-1:111111111111:key/00000000-0000-0000-0000-000000000000"
  }
}

inputs = {
  name              = local.name
  vpc_id            = dependency.vpc.outputs.vpc_id
  subnet_group_name = dependency.vpc.outputs.elasticache_subnet_group_name
  kms_key_arn       = dependency.kms.outputs.key_arn

  engine_version         = "7.1"
  parameter_group_family = "redis7"
}
