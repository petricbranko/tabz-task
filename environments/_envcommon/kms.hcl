# ---------------------------------------------------------------------------------------------------------------------
# KMS - one customer managed key per environment for application data at rest
# (Secrets Manager secret + ElastiCache at-rest encryption). A CMK, unlike the AWS managed keys, gives us an
# auditable key policy, rotation control and the ability to revoke access independently of IAM.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl")).locals
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals

  name = "${local.common.project}-${local.env.env}"
}

terraform {
  source = "tfr:///terraform-aws-modules/kms/aws?version=${local.common.module_versions.kms}"
}

inputs = {
  description = "${local.name} application data (Secrets Manager, ElastiCache)"
  aliases     = ["${local.name}/app"]

  enable_key_rotation = true

  # Root-account statement only; access is granted through IAM policies on the consuming roles
  # (e.g. the ECS task execution role gets kms:Decrypt via Secrets Manager).
  enable_default_policy = true
}
