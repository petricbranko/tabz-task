################################################################################
# Placement
################################################################################

variable "name" {
  description = "Service name, e.g. tabz-prod-web. Used for the service, task family, SG, target group (max 32 chars)"
  type        = string

  validation {
    condition     = length(var.name) <= 32
    error_message = "name must be at most 32 characters (ALB target group name limit)."
  }
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID (for the security group and target group)"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the task ENIs"
  type        = list(string)
}

variable "capacity_provider_strategy" {
  description = "Capacity provider strategy, e.g. FARGATE base + FARGATE_SPOT for burst"
  type = map(object({
    capacity_provider = string
    base              = optional(number)
    weight            = optional(number)
  }))
  default = {
    fargate = {
      capacity_provider = "FARGATE"
      base              = 1
      weight            = 1
    }
  }
}

################################################################################
# Task
################################################################################

variable "cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory in MiB"
  type        = number
  default     = 512
}

variable "cpu_architecture" {
  description = "X86_64 or ARM64 (Graviton, ~20% cheaper if the image is multi-arch)"
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "container" {
  description = <<-EOT
    Main application container.
      secrets        - map of ENV_VAR => Secrets Manager valueFrom (ARN or ARN:json-key::), injected at task start
      writable_paths - paths that need to be writable despite the read-only root file system
  EOT
  type = object({
    name                 = optional(string, "app")
    image                = string
    port                 = number
    command              = optional(list(string))
    environment          = optional(map(string), {})
    secrets              = optional(map(string), {})
    health_check_command = optional(list(string))
    writable_paths       = optional(list(string), [])
  })
}

variable "sidecars" {
  description = "Additional containers in the task (e.g. probes, log routers). Non-essential by default"
  type = map(object({
    image       = string
    essential   = optional(bool, false)
    command     = optional(list(string))
    environment = optional(map(string), {})
    secrets     = optional(map(string), {})
  }))
  default = {}
}

variable "volume_init_image" {
  description = "Image of the init container that makes writable_paths writable for a non-root app user"
  type        = string
  default     = "public.ecr.aws/docker/library/busybox:1.37"
}

variable "log_retention_in_days" {
  description = "CloudWatch log retention for all containers of the service"
  type        = number
  default     = 14
}

################################################################################
# IAM
################################################################################

variable "secret_arns" {
  description = "Secrets Manager secret ARNs the execution role may read (must cover every valueFrom used)"
  type        = list(string)
  default     = []
}

variable "kms_key_arns" {
  description = "KMS keys encrypting those secrets; decrypt is only allowed via Secrets Manager"
  type        = list(string)
  default     = []
}

variable "task_role_statements" {
  description = "IAM statements for the task role (the application's own runtime permissions)"
  type        = any
  default     = null
}

variable "enable_execute_command" {
  description = "Enable ECS Exec (SSM) for interactive debugging, e.g. to run redis-cli from inside the task"
  type        = bool
  default     = false
}

################################################################################
# Load balancing
################################################################################

variable "load_balancer" {
  description = "Attach the service to a shared ALB listener. null = no load balancer (worker service)"
  type = object({
    listener_arn         = string
    alb_arn_suffix       = string
    security_group_id    = string
    priority             = number
    path_patterns        = optional(list(string), ["/*"])
    host_headers         = optional(list(string), [])
    health_check_path    = optional(string, "/")
    health_check_matcher = optional(string, "200")
    deregistration_delay = optional(number, 30)
  })
  default = null
}

variable "health_check_grace_period_seconds" {
  description = "Seconds to ignore failing ALB health checks after a task starts"
  type        = number
  default     = 30
}

################################################################################
# Connectivity to data stores
################################################################################

variable "downstream_security_groups" {
  description = <<-EOT
    Security groups this service must reach, keyed by a short name (e.g. redis). For each entry the module adds
    an egress rule on the service SG and a matching ingress rule on the target SG, both SG-referenced.
  EOT
  type = map(object({
    security_group_id = string
    port              = number
  }))
  default = {}
}

################################################################################
# Scaling & deployment
################################################################################

variable "desired_count" {
  description = "Task count when autoscaling is disabled"
  type        = number
  default     = 1
}

variable "autoscaling" {
  description = <<-EOT
    Target tracking autoscaling. null disables it.
      requests_per_target - ALBRequestCountPerTarget target (requests per task per minute)
      cpu_target          - average CPU % target (safety net)
      scheduled_actions   - e.g. scale dev to zero outside office hours
  EOT
  type = object({
    min_capacity        = number
    max_capacity        = number
    requests_per_target = optional(number)
    cpu_target          = optional(number)
    scale_in_cooldown   = optional(number, 300)
    scale_out_cooldown  = optional(number, 60)
    scheduled_actions = optional(map(object({
      min_capacity = number
      max_capacity = number
      schedule     = string
      timezone     = optional(string)
    })))
  })
  default = null

  validation {
    condition     = var.autoscaling == null || try(var.autoscaling.min_capacity <= var.autoscaling.max_capacity, false)
    error_message = "autoscaling.min_capacity must be <= autoscaling.max_capacity."
  }
}

variable "wait_for_steady_state" {
  description = "Block apply until the deployment is stable (recommended in CD pipelines)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags (provider default_tags already cover the standard set)"
  type        = map(string)
  default     = {}
}
