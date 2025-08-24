###############################################################################
# ECS Cluster Outputs
###############################################################################

output "ecs_cluster_id" {
  description = "The ID of the ECS cluster"
  value       = module.ecs_cluster.cluster_id
}

output "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster"
  value       = module.ecs_cluster.cluster_arn
}

###############################################################################
# Networking Outputs
###############################################################################

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "ecs_security_group_id" {
  description = "ID of the ECS security group"
  value       = module.ecs_cluster.security_group_id
}

###############################################################################
# IAM Role Outputs
###############################################################################

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = module.ecs_cluster.task_execution_role_arn
}

output "ecs_task_execution_role_name" {
  description = "The name of the ECS task execution role"
  value       = module.ecs_cluster.task_execution_role_arn
}

###############################################################################
# CloudWatch Logs Outputs
###############################################################################

output "ecs_log_group_name" {
  description = "Name of the CloudWatch log group for ECS"
  value       = module.ecs_cluster.ecs_log_group_name
}

###############################################################################
# RDS Outputs
###############################################################################

output "rds_endpoint" {
  description = "The endpoint of the RDS instance"
  value       = module.rds.db_instance_endpoint
}

output "rds_db_name" {
  description = "The database name"
  value       = module.rds.db_instance_name
}

output "rds_instance_address" {
  description = "The address of the RDS instance"
  value       = module.rds.db_instance_address
}

output "rds_instance_port" {
  description = "The port of the RDS instance"
  value       = module.rds.db_instance_port
}
