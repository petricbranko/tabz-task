include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/ecs-cluster.hcl"
  merge_strategy = "deep"
}

inputs = {
  setting = [{
    name  = "containerInsights"
    value = "enabled"
  }]

  cloudwatch_log_group_retention_in_days = 7
}
