###############################################################################
# Core Infrastructure Variables
###############################################################################

variable "org" {
  type        = string
  description = "The organization name"
}

variable "project_name" {
  type        = string
  description = "The project name"
}

variable "region" {
  type        = string
  description = "The region to deploy the resources"
}

variable "infra_env" {
  type        = string
  description = "The infrastructure environment"
}

###############################################################################
# Networking Variables
###############################################################################

variable "my_ip" {
  type        = string
  description = "The IP address of the developer for SSH access"
}

###############################################################################
# ECS Configuration Variables
###############################################################################

# We always use EC2 launch type (free tier) for ECS
# Fargate has been removed to stay within free tier

variable "key_name" {
  description = "Name of the SSH key pair for EC2 instances"
  type        = string
  default     = null
}
