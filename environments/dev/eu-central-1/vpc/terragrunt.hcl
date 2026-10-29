include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/vpc.hcl"
  merge_strategy = "deep"
}

inputs = {
  # One shared NAT gateway: saves ~2x NAT hourly cost; an AZ outage only costs dev its egress.
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_flow_log = false
}
