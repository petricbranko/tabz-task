# Settings shared by every environment. Read by root.hcl and the _envcommon/*.hcl files.
locals {
  project = "tabz"

  # Pinned versions of the official terraform-aws-modules used across all environments.
  # Bumping a version here rolls out to every environment alike.
  module_versions = {
    vpc = "6.7.3"
    alb = "10.5.1"
    ecs = "7.6.1"
    kms = "4.2.2"
  }
}
