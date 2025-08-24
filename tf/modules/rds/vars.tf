########################################################
# Infrastructure Variables
########################################################

variable "name" {
  type        = string
  description = "The name of the RDS instance"
}

variable "org" {
  type        = string
  description = "The organization name"
}

variable "infra_env" {
  type        = string
  description = "The infrastructure environment"
}

variable "vpc_id" {
  type        = string
  description = "The VPC ID"
}

variable "ecs_security_group_id" {
  type        = string
  description = "The ECS security group ID"
}

variable "my_ip" {
  type        = string
  description = "The IP address of the developer for SSH access"
}

variable "public_subnets" {
  type        = list(string)
  description = "The public subnets for publicly accessible resources"
}
