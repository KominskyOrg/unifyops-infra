# Add these outputs to the existing outputs.tf file or create if not exists

# ECS Cluster Outputs
output "ecs_cluster_id" {
  description = "The ID of the ECS cluster"
  value       = module.ecs.cluster_id
}

output "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster"
  value       = module.ecs.cluster_arn
}

# Networking Outputs
output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnets
}

output "ecs_security_group_id" {
  description = "The ID of the ECS security group"
  value       = aws_security_group.ecs_sg.id
}

# IAM Role Outputs
output "ecs_execution_role_arn" {
  description = "ARN of the ECS execution role"
  value       = aws_iam_role.ecs_execution_role.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task_role.arn
}

output "ecs_task_execution_role_arn" {
  description = "The ARN of the ECS task execution role"
  value       = module.ecs.task_exec_iam_role_arn
}

output "ecs_task_execution_role_name" {
  description = "The name of the ECS task execution role"
  value       = module.ecs.task_exec_iam_role_name
}

# CloudWatch Logs
output "ecs_log_group_name" {
  description = "Name of the CloudWatch log group for ECS"
  value       = aws_cloudwatch_log_group.ecs_logs.name
}

# Add compatibility outputs if there were existing ones
# used by other modules via remote state
