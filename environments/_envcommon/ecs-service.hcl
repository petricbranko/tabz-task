# ---------------------------------------------------------------------------------------------------------------------
# ECS service - modules/ecs-service
# Wires a service unit to the shared platform units (VPC, cluster, ALB, Redis, KMS). Service-specific settings
# (image, sizing) live in environments/<env>/<region>/services/<service>/terragrunt.hcl.
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

dependency "redis" {
  config_path = "${local.region_dir}/redis"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    primary_endpoint_address = "master.mock.xxxxxx.euc1.cache.amazonaws.com"
    port                     = 6379
    security_group_id        = "sg-00000000000000002"
    secret_arn               = "arn:aws:secretsmanager:eu-central-1:111111111111:secret:mock/redis-AbCdEf"
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
  name        = local.name
  cluster_arn = dependency.ecs_cluster.outputs.arn
  vpc_id      = dependency.vpc.outputs.vpc_id
  subnet_ids  = dependency.vpc.outputs.private_subnets

  load_balancer = {
    listener_arn      = dependency.alb.outputs.listeners[local.listener_key].arn
    security_group_id = dependency.alb.outputs.security_group_id
    priority          = 100
  }

  # SG-to-SG rule pair: service -> redis:6379 egress + redis <- service ingress.
  downstream_security_groups = {
    redis = {
      security_group_id = dependency.redis.outputs.security_group_id
      port              = dependency.redis.outputs.port
    }
  }

  secret_arns  = [dependency.redis.outputs.secret_arn]
  kms_key_arns = [dependency.kms.outputs.key_arn]

  # Deep-merged with the unit's `container` (which adds image, port, health check...).
  container = {
    environment = {
      REDIS_HOST = dependency.redis.outputs.primary_endpoint_address
      REDIS_PORT = tostring(dependency.redis.outputs.port)
      REDIS_TLS  = "true"
    }
    # The one secret: injected by the ECS agent at task start from Secrets Manager (JSON key `auth_token`).
    secrets = {
      REDIS_AUTH_TOKEN = "${dependency.redis.outputs.secret_arn}:auth_token::"
    }
  }

  # Connectivity proof without writing app code: a non-essential sidecar that PINGs Redis over TLS with the
  # injected AUTH token every 30s and logs OK/FAIL to CloudWatch. It exercises exactly the path the app uses:
  # same task ENI + SG, same subnets/route tables, same secret.
  sidecars = {
    redis-probe = {
      image = "public.ecr.aws/docker/library/redis:7.4-alpine"
      command = [
        "sh", "-c",
        "while true; do if redis-cli -h \"$REDIS_HOST\" -p \"$REDIS_PORT\" --tls --cacert /etc/ssl/certs/ca-certificates.crt -a \"$REDIS_AUTH_TOKEN\" --no-auth-warning PING | grep -q PONG; then echo \"redis-probe OK host=$REDIS_HOST\"; else echo \"redis-probe FAIL host=$REDIS_HOST\"; fi; sleep 30; done",
      ]
      environment = {
        REDIS_HOST = dependency.redis.outputs.primary_endpoint_address
        REDIS_PORT = tostring(dependency.redis.outputs.port)
      }
      secrets = {
        REDIS_AUTH_TOKEN = "${dependency.redis.outputs.secret_arn}:auth_token::"
      }
    }
  }
}
