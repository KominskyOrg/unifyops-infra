variable "name" {
  description = "Base name for resources"
  type        = string
}

variable "vpc_id" {
  description = "The VPC ID where ECS resources will be deployed"
  type        = string
}

variable "public_subnets" {
  description = "List of public subnet IDs for ECS instances"
  type        = list(string)
}

variable "key_name" {
  description = "Name of the SSH key pair for EC2 instances"
  type        = string
  default     = null
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "instance_type" {
  description = "EC2 instance type for ECS container instances"
  type        = string
  default     = "t2.micro"
}

variable "min_size" {
  description = "Minimum size of EC2 Auto Scaling Group"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum size of EC2 Auto Scaling Group"
  type        = number
  default     = 1
}

variable "desired_capacity" {
  description = "Desired capacity of EC2 Auto Scaling Group"
  type        = number
  default     = 1
}

variable "my_ip" {
  description = "Your IP address for SSH access"
  type        = string
}
