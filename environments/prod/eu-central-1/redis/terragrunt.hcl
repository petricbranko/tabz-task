include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/redis.hcl"
  merge_strategy = "deep"
}

inputs = {
  # 1 primary + 2 replicas spread over 3 AZs, automatic failover + Multi-AZ (enabled by the module when > 1 node).
  # Failover promotes a replica and the primary endpoint DNS follows it; clients reconnect, no config change.
  node_type          = "cache.r7g.large"
  num_cache_clusters = 3

  snapshot_retention_limit = 7
  apply_immediately        = false # changes wait for the maintenance window
  log_retention_in_days    = 90

  secret_recovery_window_in_days = 30
}
