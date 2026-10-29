include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/redis.hcl"
  merge_strategy = "deep"
}

inputs = {
  # Single node, no replicas: no failover, but ~1/3 of the cost. Data is a cache, losing it is acceptable in dev.
  node_type          = "cache.t4g.micro"
  num_cache_clusters = 1

  snapshot_retention_limit = 0
  apply_immediately        = true
  log_retention_in_days    = 7

  secret_recovery_window_in_days = 0
}
