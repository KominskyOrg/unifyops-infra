output "db_instance_endpoint" {
  description = "The endpoint of the RDS instance"
  value       = module.db.db_instance_endpoint
}

output "db_instance_name" {
  description = "The name of the RDS instance"
  value       = module.db.db_instance_name
}

output "db_instance_address" {
  description = "The address of the RDS instance"
  value       = module.db.db_instance_address
}

output "db_instance_port" {
  description = "The port of the RDS instance"
  value       = module.db.db_instance_port
}

