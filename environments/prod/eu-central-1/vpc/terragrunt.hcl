include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/vpc.hcl"
  merge_strategy = "deep"
}

inputs = {
  # One NAT gateway per AZ: an AZ failure never takes egress away from the surviving AZs.
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  # VPC flow logs for incident response / security forensics.
  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_max_aggregation_interval               = 60
  flow_log_cloudwatch_log_group_retention_in_days = 90
}
