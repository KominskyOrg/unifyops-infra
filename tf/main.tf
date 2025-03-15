terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = local.region
  default_tags {
    tags = {
      Terraform   = "true"
      Environment = "${var.infra_env}"
      Project     = "${var.org}-${var.project_name}"
      Region      = "${var.region}"
      Org         = "${var.org}"
    }
  }
}

data "aws_availability_zones" "available" {}

locals {
  region = "us-east-1"
  name   = "${var.infra_env}-${var.org}-${var.project_name}"

  vpc_cidrs = {
    dev     = "10.0.0.0/16"
    staging = "10.1.0.0/16"
    prod    = "10.2.0.0/16"
  }

  vpc_cidr = local.vpc_cidrs[var.infra_env]
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {}
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 4)]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  tags = {
  }
}

# SSH Security Group
resource "aws_security_group" "ssh" {
  name        = "${local.name}-ssh"
  description = "Security group for SSH access from developer IPs"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH from developer IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.name}-ssh-sg"
    }
  )
}

# Web Security Group for HTTP/HTTPS
resource "aws_security_group" "web" {
  name        = "${local.name}-web"
  description = "Security group for HTTP/HTTPS traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.name}-web-sg"
    }
  )
}

# Output the security group IDs
output "ssh_security_group_id" {
  description = "ID of the SSH security group"
  value       = aws_security_group.ssh.id
}

output "web_security_group_id" {
  description = "ID of the web security group"
  value       = aws_security_group.web.id
}
