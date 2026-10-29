################################################################################
# Auth token
#
# ElastiCache has no "managed password" integration with Secrets Manager (unlike RDS), so the token is generated
# here and written to the secret that the application reads. The value is stored (sensitive) in this unit's
# state: see README "Trade-offs" for why, and how to remove it once the official module exposes `auth_token_wo`.
################################################################################

resource "random_password" "auth_token" {
  length = 64

  # ElastiCache AUTH tokens allow printable ASCII except space, '"', '/' and '@'.
  special          = true
  override_special = "!&#$^<>-"
}

################################################################################
# Secret consumed by the application (official terraform-aws-modules/secrets-manager)
################################################################################

module "secret" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "2.2.0"

  name        = "${var.name}/redis"
  description = "Connection details and AUTH token for the ${var.name} Redis replication group"
  kms_key_id  = var.kms_key_arn

  recovery_window_in_days = var.secret_recovery_window_in_days

  secret_string = jsonencode({
    host       = module.redis.replication_group_primary_endpoint_address
    reader     = module.redis.replication_group_reader_endpoint_address
    port       = var.port
    tls        = true
    auth_token = random_password.auth_token.result
  })

  tags = var.tags
}

################################################################################
# Replication group (official terraform-aws-modules/elasticache)
################################################################################

module "redis" {
  source  = "terraform-aws-modules/elasticache/aws"
  version = "1.11.2"

  replication_group_id = var.name
  description          = "${var.name} Redis replication group"

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = var.port

  # Cluster mode disabled: one shard, 1 primary + N replicas. Sufficient for a cache / session store and keeps
  # clients simple (no cluster-aware client needed).
  cluster_mode_enabled       = false
  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = var.num_cache_clusters > 1
  multi_az_enabled           = var.num_cache_clusters > 1

  # Encryption everywhere + AUTH. Clients must connect with TLS (rediss://).
  at_rest_encryption_enabled = true
  kms_key_arn                = var.kms_key_arn
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  auth_token                 = random_password.auth_token.result

  maintenance_window         = var.maintenance_window
  snapshot_window            = var.snapshot_window
  snapshot_retention_limit   = var.snapshot_retention_limit
  apply_immediately          = var.apply_immediately
  auto_minor_version_upgrade = true

  # Networking: dedicated data subnets, dedicated security group with NO ingress by default.
  # Consumers (ECS services) add their own ingress rule referencing their SG - see modules/ecs-service.
  vpc_id                = var.vpc_id
  create_subnet_group   = false
  subnet_group_name     = var.subnet_group_name
  create_security_group = true
  security_group_name   = "${var.name}-redis"
  security_group_rules  = {}

  create_parameter_group = true
  parameter_group_family = var.parameter_group_family
  parameters             = var.parameters

  log_delivery_configuration = {
    slow-log = {
      destination_type                       = "cloudwatch-logs"
      log_format                             = "json"
      cloudwatch_log_group_retention_in_days = var.log_retention_in_days
    }
  }

  tags = var.tags
}
