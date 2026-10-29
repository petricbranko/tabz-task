# ---------------------------------------------------------------------------------------------------------------------
# ROOT TERRAGRUNT CONFIGURATION
# Included by every unit. Owns everything that must be identical everywhere: remote state, provider, tags.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  env_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  project    = local.common_vars.locals.project
  env        = local.env_vars.locals.env
  account_id = local.env_vars.locals.account_id
  aws_region = local.region_vars.locals.aws_region

  # TG_BACKEND=local switches every unit to a local backend so `validate` / `plan` with mocks can run
  # without an AWS account or state bucket (used by CI and for quick local checks). Default is S3.
  backend = get_env("TG_BACKEND", "s3")

  default_tags = {
    Project     = local.project
    Environment = local.env
    ManagedBy   = "terragrunt"
    Repository  = "tabz-task"
    Unit        = path_relative_to_include()
  }
}

remote_state {
  backend = local.backend

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    s3 = {
      # One state bucket per account + region. Created on first run with `--backend-bootstrap`
      # (versioned, encrypted, public access blocked, TLS-only policy).
      bucket       = "${local.project}-tfstate-${local.account_id}-${local.aws_region}"
      key          = "${path_relative_to_include()}/terraform.tfstate"
      region       = local.aws_region
      encrypt      = true
      use_lockfile = true # S3 native locking (Terraform >= 1.10), no DynamoDB table needed
    }
    local = {
      path = "${get_parent_terragrunt_dir()}/.local-state/${path_relative_to_include()}/terraform.tfstate"
    }
  }[local.backend]
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"

      # Guard rail: a prod unit can never be applied with dev credentials (and vice versa).
      allowed_account_ids = ["${local.account_id}"]

      default_tags {
        tags = ${jsonencode(local.default_tags)}
      }
    }
  EOF
}

generate "terraform_version" {
  path      = "terraform_version.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.11, < 2.0"
    }
  EOF
}
