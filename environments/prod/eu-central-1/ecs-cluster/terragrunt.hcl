include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/ecs-cluster.hcl"
  merge_strategy = "deep"
}

inputs = {
  # Enhanced observability: per-task / per-container metrics, needed to right-size and debug in prod.
  setting = [{
    name  = "containerInsights"
    value = "enhanced"
  }]

  cloudwatch_log_group_retention_in_days = 90
}
