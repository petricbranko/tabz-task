# ---------------------------------------------------------------------------------------------------------------------
# ALB access logs bucket (prod only) - official terraform-aws-modules/s3-bucket
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl")).locals
}

terraform {
  source = "tfr:///terraform-aws-modules/s3-bucket/aws?version=${local.common.module_versions.s3_bucket}"
}

inputs = {
  bucket = "tabz-prod-alb-logs-${include.root.locals.account_id}"

  # ALB log delivery only supports SSE-S3 (not SSE-KMS).
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = { sse_algorithm = "AES256" }
    }
  }

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  attach_elb_log_delivery_policy        = true
  attach_lb_log_delivery_policy         = true
  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  lifecycle_rule = [{
    id      = "expire-access-logs"
    enabled = true
    filter  = {}
    expiration = {
      days = 90
    }
  }]
}
