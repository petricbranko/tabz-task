output "service_name" {
  description = "Name of the ECS service"
  value       = module.service.name
}

output "service_id" {
  description = "ARN of the ECS service"
  value       = module.service.id
}

output "task_definition_arn" {
  description = "ARN of the current task definition revision"
  value       = module.service.task_definition_arn
}

output "security_group_id" {
  description = "Security group of the tasks"
  value       = aws_security_group.this.id
}

output "task_exec_role_arn" {
  description = "Execution role (image pull, logs, secret injection)"
  value       = module.service.task_exec_iam_role_arn
}

output "task_role_arn" {
  description = "Task role (application runtime permissions)"
  value       = module.service.tasks_iam_role_arn
}

output "target_group_arn" {
  description = "ALB target group ARN (null when no load balancer)"
  value       = try(aws_lb_target_group.this[0].arn, null)
}
