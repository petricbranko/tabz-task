include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/kms.hcl"
  merge_strategy = "deep"
}

inputs = {
  deletion_window_in_days = 7
}
