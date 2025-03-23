output "cluster_id" {
  description = "ID of the ECS Cluster"
  value       = module.ecs.cluster_id
}

output "cluster_arn" {
  description = "ARN of the ECS Cluster"
  value       = module.ecs.cluster_arn
}

output "cluster_name" {
  description = "Name of the ECS Cluster"
  value       = module.ecs.cluster_name
}

output "autoscaling_group_name" {
  description = "Name of the autoscaling group for ECS"
  value       = aws_autoscaling_group.ecs_asg.name
}

output "security_group_id" {
  description = "ID of the security group for ECS"
  value       = aws_security_group.ecs_sg.id
}

output "task_execution_role_arn" {
  description = "ARN of ECS task execution role"
  value       = module.ecs.task_exec_iam_role_arn
}

output "ecs_log_group_name" {
  description = "Name of the CloudWatch log group for ECS"
  value       = module.ecs.cloudwatch_log_group_name
}
