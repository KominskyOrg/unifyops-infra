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
  region = var.region
}

data "aws_availability_zones" "available" {}

locals {
  name = "${var.org}-${var.project_name}-${var.infra_env}"

  tags = {
    Project     = var.project_name
    Environment = var.infra_env
    Owner       = var.org
    ManagedBy   = "Terraform"
  }

  vpc_cidrs = {
    dev     = "10.0.0.0/16"
    staging = "10.1.0.0/16"
    prod    = "10.2.0.0/16"
  }

  vpc_cidr = local.vpc_cidrs[var.infra_env]
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}

# VPC, Subnets, and network configuration
# ======================================
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = false
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.tags
}

# ECS Cluster 
# ==========
module "ecs_cluster" {
  source = "./modules/ecs"

  name           = local.name
  vpc_id         = module.vpc.vpc_id
  public_subnets = module.vpc.public_subnets
  key_name       = var.key_name
  my_ip          = var.my_ip
  # Default values can be overridden per environment
  instance_type    = "t2.micro"
  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  tags = local.tags
}
