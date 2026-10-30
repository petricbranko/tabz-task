include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/ecs-service.hcl"
  merge_strategy = "deep"
}

inputs = {
  # Promoted from dev once validated there.
  container = {
    image                = "public.ecr.aws/nginx/nginx-unprivileged:1.27-alpine"
    port                 = 8080
    health_check_command = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1"]
    writable_paths       = ["/tmp", "/var/cache/nginx"]
  }

  cpu    = 512
  memory = 1024

  # Baseline of 3 on-demand tasks (one per AZ, never interrupted); capacity above the baseline is split
  # 1:1 between on-demand and Spot to cut the cost of peaks without betting availability on Spot.
  capacity_provider_strategy = {
    on_demand = {
      capacity_provider = "FARGATE"
      base              = 3
      weight            = 1
    }
    spot = {
      capacity_provider = "FARGATE_SPOT"
      weight            = 1
    }
  }

  autoscaling = {
    min_capacity        = 3
    max_capacity        = 12
    requests_per_target = 1000
    cpu_target          = 60 # lower than dev: more headroom while new tasks start (~60s on Fargate)
    scale_out_cooldown  = 60
    scale_in_cooldown   = 300
  }

  health_check_grace_period_seconds = 60

  # Off in prod (the redis-probe sidecar covers connectivity); flip on for break-glass debugging -
  # sessions are audited in the cluster exec log group.
  enable_execute_command = false
  log_retention_in_days  = 90
}
