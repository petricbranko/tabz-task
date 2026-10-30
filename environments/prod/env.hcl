# Environment-wide settings for prod. Unit-level sizing lives in each unit's terragrunt.hcl.
locals {
  env        = "prod"
  account_id = "015234777927" # same account as dev for this exercise; a real setup uses a dedicated prod account

  vpc_cidr = "10.20.0.0/16"
  az_count = 3 # survive the loss of a full AZ with headroom

  # ACM certificate for the ALB. Set it to enable HTTPS + HTTP->HTTPS redirect (needs a domain).
  certificate_arn = ""
}
