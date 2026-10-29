include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/alb.hcl"
  merge_strategy = "deep"
}

inputs = {
  # Disposable environment: allow `destroy` without a manual step.
  enable_deletion_protection = false
}
