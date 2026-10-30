# Environment-wide settings for prod. Unit-level sizing lives in each unit's terragrunt.hcl.
locals {
  env = "prod"
  # Target account; override with AWS_ACCOUNT_ID to plan in another account. The provider refuses any other
  # account, and the state bucket name follows it.
  # Same default as dev for this exercise; a real setup uses a dedicated prod account.
  account_id = get_env("AWS_ACCOUNT_ID", "015234777927")

  vpc_cidr = "10.20.0.0/16"
  az_count = 3 # survive the loss of a full AZ with headroom

  # ACM certificate for the ALB. Set it to enable HTTPS + HTTP->HTTPS redirect (needs a domain).
  certificate_arn = ""
}
