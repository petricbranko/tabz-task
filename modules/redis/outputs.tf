output "replication_group_id" {
  description = "ID of the replication group"
  value       = module.redis.replication_group_id
}

output "primary_endpoint_address" {
  description = "Primary (read/write) endpoint; follows the primary on failover"
  value       = module.redis.replication_group_primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Reader endpoint load balancing across replicas"
  value       = module.redis.replication_group_reader_endpoint_address
}

output "port" {
  description = "Redis port"
  value       = var.port
}

output "security_group_id" {
  description = "Security group attached to the cache nodes. Consumers add ingress rules to it"
  value       = module.redis.security_group_id
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding host/port/auth_token"
  value       = module.secret.secret_arn
}
