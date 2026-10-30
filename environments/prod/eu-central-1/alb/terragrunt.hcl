include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/alb.hcl"
  merge_strategy = "deep"
}

dependency "alb_logs" {
  config_path = "../alb-logs"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    s3_bucket_id = "tabz-prod-alb-logs-000000000000"
  }
}

inputs = {
  enable_deletion_protection = true

  access_logs = {
    bucket = dependency.alb_logs.outputs.s3_bucket_id
    prefix = "alb"
  }
}
