variable "name" {
  description = "Name of the replication group; also used as prefix for the secret and security group"
  type        = string
}

variable "vpc_id" {
  description = "VPC the replication group lives in"
  type        = string
}

variable "subnet_group_name" {
  description = "Existing ElastiCache subnet group (created by the VPC module from the data subnets)"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key used for at-rest encryption of the cache and the secret"
  type        = string
}

variable "engine_version" {
  description = "Redis OSS engine version"
  type        = string
  default     = "7.1"
}

variable "parameter_group_family" {
  description = "Parameter group family matching engine_version"
  type        = string
  default     = "redis7"
}

variable "parameters" {
  description = "Parameter overrides for the parameter group"
  type        = list(map(string))
  default     = []
}

variable "node_type" {
  description = "Cache node instance type"
  type        = string
}

variable "num_cache_clusters" {
  description = "Number of nodes (1 primary + N-1 replicas). > 1 enables automatic failover and Multi-AZ"
  type        = number
  default     = 1

  validation {
    condition     = var.num_cache_clusters >= 1 && var.num_cache_clusters <= 6
    error_message = "num_cache_clusters must be between 1 and 6."
  }
}

variable "port" {
  description = "Port Redis listens on"
  type        = number
  default     = 6379
}

variable "maintenance_window" {
  description = "Weekly maintenance window (UTC)"
  type        = string
  default     = "sun:03:00-sun:04:00"
}

variable "snapshot_window" {
  description = "Daily snapshot window (UTC); must not overlap the maintenance window"
  type        = string
  default     = "01:00-02:00"
}

variable "snapshot_retention_limit" {
  description = "Days to keep automatic snapshots (0 disables snapshots)"
  type        = number
  default     = 0
}

variable "apply_immediately" {
  description = "Apply modifications immediately instead of during the maintenance window"
  type        = bool
  default     = false
}

variable "log_retention_in_days" {
  description = "Retention for the slow-log CloudWatch log group"
  type        = number
  default     = 14
}

variable "secret_recovery_window_in_days" {
  description = "Recovery window for the secret; 0 forces immediate deletion (only sensible for ephemeral envs)"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags (provider default_tags already cover the standard set)"
  type        = map(string)
  default     = {}
}
