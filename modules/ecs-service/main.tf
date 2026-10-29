################################################################################
# Reusable, opinionated Fargate service.
#
# Wraps the official terraform-aws-modules/ecs//modules/service and adds the pieces every service in this platform
# needs but the upstream module deliberately leaves out:
#   - its own ALB target group + listener rule on the shared ALB
#   - bidirectional security group wiring to the ALB (upstream) and to data stores (downstream)
#   - least-privilege execution role for injecting Secrets Manager values (incl. KMS decrypt)
#   - hardened container defaults (read-only root FS, non-root image, no public IP)
################################################################################

data "aws_region" "current" {}

locals {
  lb_enabled = var.load_balancer != null

  # Fargate gives no tmpfs; writable paths on a read-only root FS are backed by task-scoped ephemeral volumes.
  scratch_volumes = { for i, path in var.container.writable_paths : "scratch-${i}" => path }
  scratch_mounts = [for vol, path in local.scratch_volumes : {
    sourceVolume  = vol
    containerPath = path
    readOnly      = false
  }]

  # Those volumes are created root-owned, so a non-root app user cannot write to them. A short-lived init container
  # opens them up before the app starts (the app waits for it to exit successfully).
  volume_init_enabled = length(local.scratch_volumes) > 0

  volume_init_container = {
    for k, v in {
      volume-init = {
        name        = "volume-init"
        image       = var.volume_init_image
        essential   = false
        user        = "0"
        command     = ["sh", "-c", "chmod 1777 ${join(" ", values(local.scratch_volumes))}"]
        mountPoints = local.scratch_mounts

        readonlyRootFilesystem                 = true
        cloudwatch_log_group_retention_in_days = var.log_retention_in_days
      }
    } : k => v if local.volume_init_enabled
  }

  app_container = {
    name      = var.container.name
    image     = var.container.image
    essential = true
    command   = var.container.command

    portMappings = [{
      name          = "http"
      containerPort = var.container.port
      protocol      = "tcp"
    }]

    environment = [for k, v in var.container.environment : { name = k, value = v }]
    secrets     = [for k, v in var.container.secrets : { name = k, valueFrom = v }]

    readonlyRootFilesystem = true
    mountPoints            = local.scratch_mounts
    dependsOn              = local.volume_init_enabled ? [{ containerName = "volume-init", condition = "SUCCESS" }] : null

    healthCheck = var.container.health_check_command == null ? null : {
      command     = var.container.health_check_command
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }

    cloudwatch_log_group_retention_in_days = var.log_retention_in_days
  }

  sidecar_containers = {
    for k, s in var.sidecars : k => {
      name                                   = k
      image                                  = s.image
      essential                              = s.essential
      command                                = s.command
      environment                            = [for ek, ev in s.environment : { name = ek, value = ev }]
      secrets                                = [for sk, sv in s.secrets : { name = sk, valueFrom = sv }]
      readonlyRootFilesystem                 = true
      cloudwatch_log_group_retention_in_days = var.log_retention_in_days
    }
  }
}

################################################################################
# Service, task definition, IAM roles
################################################################################

module "service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "7.6.1"

  name        = var.name
  cluster_arn = var.cluster_arn

  # Task definition
  cpu    = var.cpu
  memory = var.memory
  runtime_platform = {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }
  container_definitions = merge({ (var.container.name) = local.app_container }, local.volume_init_container, local.sidecar_containers)
  volume                = { for vol, _ in local.scratch_volumes : vol => {} }

  # Service
  launch_type                        = "FARGATE"
  capacity_provider_strategy         = var.capacity_provider_strategy
  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  deployment_circuit_breaker = {
    enable   = true
    rollback = true
  }
  availability_zone_rebalancing = "ENABLED"
  enable_execute_command        = var.enable_execute_command
  propagate_tags                = "SERVICE"
  wait_for_steady_state         = var.wait_for_steady_state

  health_check_grace_period_seconds = local.lb_enabled ? var.health_check_grace_period_seconds : null
  load_balancer = local.lb_enabled ? {
    app = {
      container_name   = var.container.name
      container_port   = var.container.port
      target_group_arn = aws_lb_target_group.this[0].arn
    }
  } : null

  # Networking: private subnets only, never a public IP.
  subnet_ids       = var.subnet_ids
  assign_public_ip = false

  # The SG is created in this wrapper (see below) rather than by the upstream module: upstream looks up the first
  # subnet with a data source, which fails on `plan` against an empty account where subnet IDs are still mocks.
  create_security_group = false
  security_group_ids    = [aws_security_group.this.id]

  # Execution role: used by the ECS agent to pull the image, write logs and inject secrets at task start.
  task_exec_secret_arns = var.secret_arns
  task_exec_iam_statements = length(var.kms_key_arns) == 0 ? null : [{
    sid       = "DecryptSecretsViaSecretsManager"
    actions   = ["kms:Decrypt"]
    resources = var.kms_key_arns
    condition = [{
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${data.aws_region.current.region}.amazonaws.com"]
    }]
  }]

  # Task role: what the application itself may call at runtime. ECS Exec permissions are added by the module
  # when enable_execute_command = true.
  tasks_iam_role_statements = var.task_role_statements

  # Upstream enables CPU + memory autoscaling by default; keep a fixed desired_count instead.
  enable_autoscaling = false

  tags = var.tags
}

################################################################################
# Load balancer integration (shared ALB, per-service target group + rule)
################################################################################

resource "aws_lb_target_group" "this" {
  count = local.lb_enabled ? 1 : 0

  name        = substr(var.name, 0, 32)
  vpc_id      = var.vpc_id
  port        = var.container.port
  protocol    = "HTTP"
  target_type = "ip" # required for awsvpc / Fargate

  deregistration_delay = var.load_balancer.deregistration_delay

  health_check {
    enabled             = true
    path                = var.load_balancer.health_check_path
    matcher             = var.load_balancer.health_check_matcher
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = var.tags
}

resource "aws_lb_listener_rule" "this" {
  count = local.lb_enabled ? 1 : 0

  listener_arn = var.load_balancer.listener_arn
  priority     = var.load_balancer.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  condition {
    path_pattern {
      values = var.load_balancer.path_patterns
    }
  }

  dynamic "condition" {
    for_each = length(var.load_balancer.host_headers) > 0 ? [1] : []

    content {
      host_header {
        values = var.load_balancer.host_headers
      }
    }
  }

  tags = var.tags
}

################################################################################
# Security groups
#
# Every rule is SG-referenced (no CIDRs except HTTPS egress to AWS APIs). Dependencies flow
# network -> data stores -> service, so the service is the only unit that knows both sides: it "registers"
# itself, i.e. the ALB may reach it and it may reach its downstreams. Destroying the service removes exactly its
# own rules and nothing else.
################################################################################

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-"
  description = "ECS service ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  count = local.lb_enabled ? 1 : 0

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.load_balancer.security_group_id
  from_port                    = var.container.port
  to_port                      = var.container.port
  ip_protocol                  = "tcp"
  description                  = "ALB to app port"

  tags = var.tags
}

# Accepted risk: tasks need HTTPS to AWS APIs / public registries via NAT. Narrowing to VPC endpoint SGs + the S3
# prefix list is possible once every dependency (incl. images) is reachable privately.
#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS to AWS APIs and image registries (NAT or VPC endpoints)"

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "alb_to_service" {
  count = local.lb_enabled ? 1 : 0

  security_group_id            = var.load_balancer.security_group_id
  referenced_security_group_id = aws_security_group.this.id
  from_port                    = var.container.port
  to_port                      = var.container.port
  ip_protocol                  = "tcp"
  description                  = "ALB to ${var.name}"

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "to_downstream" {
  for_each = var.downstream_security_groups

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value.security_group_id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
  description                  = "To ${each.key}"

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "downstream_from_service" {
  for_each = var.downstream_security_groups

  security_group_id            = each.value.security_group_id
  referenced_security_group_id = aws_security_group.this.id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
  description                  = "${var.name} to ${each.key}"

  tags = var.tags
}
