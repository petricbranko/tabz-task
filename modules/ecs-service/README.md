# ecs-service

Reusable, opinionated Fargate service for this platform. Thin wrapper around the official
[`terraform-aws-modules/ecs//modules/service`](https://registry.terraform.io/modules/terraform-aws-modules/ecs/aws/latest/submodules/service)
that adds what every service here needs and upstream intentionally leaves out:

| Concern | What the wrapper does |
|---|---|
| Load balancing | Own target group (`ip` targets) + listener rule on the **shared** ALB; no ALB changes per service |
| Network security | Creates the service SG. ALB → service is SG-referenced in both directions: the module also writes the ALB egress rule, so the ALB can only reach registered services |
| Hardening | Read-only root FS, private subnets, no public IP. Writable paths are ephemeral task volumes, made writable for non-root images by an init container |
| Deployments | Rolling 100%/200%, circuit breaker with automatic rollback, AZ rebalancing |

## Usage

```hcl
module "web" {
  source = "../../modules/ecs-service"

  name        = "tabz-dev-web"
  cluster_arn = module.cluster.arn
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnets

  container = {
    image          = "public.ecr.aws/nginx/nginx-unprivileged:1.27-alpine"
    port           = 8080
    writable_paths = ["/tmp"]
  }

  load_balancer = {
    listener_arn      = module.alb.listeners["http"].arn
    security_group_id = module.alb.security_group_id
    priority          = 100
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.41, < 7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.41, < 7.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_service"></a> [service](#module\_service) | terraform-aws-modules/ecs/aws//modules/service | 7.6.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_lb_listener_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.alb_to_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_capacity_provider_strategy"></a> [capacity\_provider\_strategy](#input\_capacity\_provider\_strategy) | Capacity provider strategy, e.g. FARGATE base + FARGATE\_SPOT for burst | <pre>map(object({<br/>    capacity_provider = string<br/>    base              = optional(number)<br/>    weight            = optional(number)<br/>  }))</pre> | <pre>{<br/>  "fargate": {<br/>    "base": 1,<br/>    "capacity_provider": "FARGATE",<br/>    "weight": 1<br/>  }<br/>}</pre> | no |
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of the ECS cluster | `string` | n/a | yes |
| <a name="input_container"></a> [container](#input\_container) | Main application container.<br/>  writable\_paths - paths that need to be writable despite the read-only root file system | <pre>object({<br/>    name                 = optional(string, "app")<br/>    image                = string<br/>    port                 = number<br/>    command              = optional(list(string))<br/>    environment          = optional(map(string), {})<br/>    health_check_command = optional(list(string))<br/>    writable_paths       = optional(list(string), [])<br/>  })</pre> | n/a | yes |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Task CPU units (256 = 0.25 vCPU) | `number` | `256` | no |
| <a name="input_cpu_architecture"></a> [cpu\_architecture](#input\_cpu\_architecture) | X86\_64 or ARM64 (Graviton, ~20% cheaper if the image is multi-arch) | `string` | `"X86_64"` | no |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count) | Number of tasks to run | `number` | `1` | no |
| <a name="input_enable_execute_command"></a> [enable\_execute\_command](#input\_enable\_execute\_command) | Enable ECS Exec (SSM) for interactive debugging inside running tasks | `bool` | `false` | no |
| <a name="input_health_check_grace_period_seconds"></a> [health\_check\_grace\_period\_seconds](#input\_health\_check\_grace\_period\_seconds) | Seconds to ignore failing ALB health checks after a task starts | `number` | `30` | no |
| <a name="input_load_balancer"></a> [load\_balancer](#input\_load\_balancer) | Attach the service to a shared ALB listener. null = no load balancer (worker service) | <pre>object({<br/>    listener_arn         = string<br/>    security_group_id    = string<br/>    priority             = number<br/>    path_patterns        = optional(list(string), ["/*"])<br/>    host_headers         = optional(list(string), [])<br/>    health_check_path    = optional(string, "/")<br/>    health_check_matcher = optional(string, "200")<br/>    deregistration_delay = optional(number, 30)<br/>  })</pre> | `null` | no |
| <a name="input_log_retention_in_days"></a> [log\_retention\_in\_days](#input\_log\_retention\_in\_days) | CloudWatch log retention for all containers of the service | `number` | `14` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Task memory in MiB | `number` | `512` | no |
| <a name="input_name"></a> [name](#input\_name) | Service name, e.g. tabz-prod-web. Used for the service, task family, SG, target group (max 32 chars) | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Private subnets for the task ENIs | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags (provider default\_tags already cover the standard set) | `map(string)` | `{}` | no |
| <a name="input_task_role_statements"></a> [task\_role\_statements](#input\_task\_role\_statements) | IAM statements for the task role (the application's own runtime permissions) | `any` | `null` | no |
| <a name="input_volume_init_image"></a> [volume\_init\_image](#input\_volume\_init\_image) | Image of the init container that makes writable\_paths writable for a non-root app user | `string` | `"public.ecr.aws/docker/library/busybox:1.37"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID (for the security group and target group) | `string` | n/a | yes |
| <a name="input_wait_for_steady_state"></a> [wait\_for\_steady\_state](#input\_wait\_for\_steady\_state) | Block apply until the deployment is stable (recommended in CD pipelines) | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group of the tasks |
| <a name="output_service_id"></a> [service\_id](#output\_service\_id) | ARN of the ECS service |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Name of the ECS service |
| <a name="output_target_group_arn"></a> [target\_group\_arn](#output\_target\_group\_arn) | ALB target group ARN (null when no load balancer) |
| <a name="output_task_definition_arn"></a> [task\_definition\_arn](#output\_task\_definition\_arn) | ARN of the current task definition revision |
| <a name="output_task_exec_role_arn"></a> [task\_exec\_role\_arn](#output\_task\_exec\_role\_arn) | Execution role (image pull, logs, secret injection) |
| <a name="output_task_role_arn"></a> [task\_role\_arn](#output\_task\_role\_arn) | Task role (application runtime permissions) |
<!-- END_TF_DOCS -->
