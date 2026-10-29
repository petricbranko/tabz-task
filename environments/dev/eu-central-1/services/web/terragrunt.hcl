include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/ecs-service.hcl"
  merge_strategy = "deep"
}

inputs = {
  # The image tag is pinned per environment on purpose: dev runs a tag first, prod is promoted to it later.
  container = {
    image                = "public.ecr.aws/nginx/nginx-unprivileged:1.27-alpine"
    port                 = 8080
    health_check_command = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1"]
    writable_paths       = ["/tmp", "/var/cache/nginx"]
  }

  cpu    = 256
  memory = 512

  # Spot only: up to ~70% cheaper; interruptions are acceptable in dev.
  capacity_provider_strategy = {
    spot = {
      capacity_provider = "FARGATE_SPOT"
      weight            = 1
    }
  }

  desired_count = 1

  enable_execute_command = true
  log_retention_in_days  = 7
}
