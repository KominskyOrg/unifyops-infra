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
# Developer Variables
###############################################################################

variable "my_ip" {
  type        = string
  description = "The IP address of the developer"
}

###############################################################################
# EC2 Variables
###############################################################################

variable "instance_type" {
  description = "The type of EC2 instance to launch"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Name of the SSH key pair to use for the instance"
  type        = string
  default     = null
}
