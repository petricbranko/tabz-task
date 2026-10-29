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

  autoscaling = {
    min_capacity        = 1
    max_capacity        = 2
    requests_per_target = 1000
    cpu_target          = 70

    # Scale to zero outside office hours (Mon-Fri 07:00-20:00 Europe/Belgrade, weekends off). Running `apply`
    # while scaled down resets min/max and wakes dev up until the next evening: intended, you are using it.
    scheduled_actions = {
      night = {
        min_capacity = 0
        max_capacity = 0
        schedule     = "cron(0 20 ? * MON-FRI *)"
        timezone     = "Europe/Belgrade"
      }
      morning = {
        min_capacity = 1
        max_capacity = 2
        schedule     = "cron(0 7 ? * MON-FRI *)"
        timezone     = "Europe/Belgrade"
      }
    }
  }

  enable_execute_command = true
  log_retention_in_days  = 7
}
