# Environment-wide settings for dev. Unit-level sizing lives in each unit's terragrunt.hcl.
locals {
  env        = "dev"
  account_id = "015234777927"

  vpc_cidr = "10.10.0.0/16"
  az_count = 2 # ALB minimum; cost over resilience in dev

  # ACM certificate for the ALB. Empty = HTTP-only listener (fine for a plan / throwaway dev).
  certificate_arn = ""
}
