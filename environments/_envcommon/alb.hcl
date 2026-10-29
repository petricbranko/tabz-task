# ---------------------------------------------------------------------------------------------------------------------
# ALB - official terraform-aws-modules/alb
# One shared, internet-facing ALB per environment. It only owns listeners with a default 404; every ECS service
# brings its own target group + listener rule (see modules/ecs-service), so adding a service never touches this unit.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  common     = read_terragrunt_config(find_in_parent_folders("common.hcl")).locals
  env        = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  region_dir = dirname(find_in_parent_folders("region.hcl"))

  name      = "${local.common.project}-${local.env.env}"
  https     = local.env.certificate_arn != ""
  not_found = { content_type = "text/plain", message_body = "Not Found", status_code = "404" }

  # HCL conditionals need both branches to have the same type, hence the map lookups below.
  http_listener = {
    true = {
      port     = 80
      protocol = "HTTP"
      redirect = { port = "443", protocol = "HTTPS", status_code = "HTTP_301" }
    }
    false = {
      port           = 80
      protocol       = "HTTP"
      fixed_response = local.not_found
    }
  }[tostring(local.https)]

  https_listener = {
    port            = 443
    protocol        = "HTTPS"
    ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
    certificate_arn = local.env.certificate_arn
    fixed_response  = local.not_found
  }
}

terraform {
  source = "tfr:///terraform-aws-modules/alb/aws?version=${local.common.module_versions.alb}"
}

dependency "vpc" {
  config_path = "${local.region_dir}/vpc"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    vpc_id         = "vpc-00000000000000000"
    public_subnets = ["subnet-00000000000000001", "subnet-00000000000000002", "subnet-00000000000000003"]
  }
}

inputs = {
  name               = local.name
  load_balancer_type = "application"
  internal           = false

  vpc_id  = dependency.vpc.outputs.vpc_id
  subnets = dependency.vpc.outputs.public_subnets

  drop_invalid_header_fields = true
  idle_timeout               = 60

  security_group_ingress_rules = {
    for k, v in {
      http  = { port = 80, enabled = true }
      https = { port = 443, enabled = local.https }
      } : k => {
      from_port   = v.port
      to_port     = v.port
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "${upper(k)} from the internet"
    } if v.enabled
  }

  # Intentionally no egress rules here: each ECS service adds an egress rule on this SG pointing at its own SG
  # and container port, so the ALB can only talk to registered services.
  security_group_egress_rules = {}

  listeners = merge(
    { http = local.http_listener },
    { for k, v in { https = local.https_listener } : k => v if local.https }
  )
}
