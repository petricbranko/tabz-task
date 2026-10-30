# Environment-wide settings for dev. Unit-level sizing lives in each unit's terragrunt.hcl.
locals {
  env = "dev"
  # Target account; override with AWS_ACCOUNT_ID to plan in another account. The provider refuses any other
  # account, and the state bucket name follows it.
  account_id = get_env("AWS_ACCOUNT_ID", "015234777927")

  vpc_cidr = "10.10.0.0/16"
  az_count = 2 # ALB minimum; cost over resilience in dev

  # ACM certificate for the ALB. Empty = HTTP-only listener (fine for a plan / throwaway dev).
  certificate_arn = ""
}
