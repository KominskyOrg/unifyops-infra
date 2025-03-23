# ECS Cluster Module

This module provisions an Amazon ECS cluster with EC2 capacity providers, optimized for free tier eligibility.

## Features

- Creates an ECS cluster using EC2 launch type (free tier eligible)
- Sets up EC2 auto-scaling group with t2.micro instances
- Configures IAM roles and policies for ECS instances
- Implements security groups with appropriate rules
- Configures CloudWatch logging for the ECS cluster

## Usage

```hcl
module "ecs_cluster" {
  source = "./modules/ecs"

  name           = "my-application"
  vpc_id         = module.vpc.vpc_id
  public_subnets = module.vpc.public_subnets
  key_name       = var.key_name

  # Optional parameters with defaults
  instance_type    = "t2.micro"
  min_size         = 1
  max_size         = 2
  desired_capacity = 1

  tags = {
    Environment = "dev"
    Project     = "my-project"
  }
}
```

## Inputs

| Name             | Description                                     | Type           | Default      | Required |
| ---------------- | ----------------------------------------------- | -------------- | ------------ | :------: |
| name             | Base name for resources                         | `string`       | n/a          |   yes    |
| vpc_id           | The VPC ID where ECS resources will be deployed | `string`       | n/a          |   yes    |
| public_subnets   | List of public subnet IDs for ECS instances     | `list(string)` | n/a          |   yes    |
| key_name         | Name of the SSH key pair for EC2 instances      | `string`       | `null`       |    no    |
| tags             | A map of tags to add to all resources           | `map(string)`  | `{}`         |    no    |
| instance_type    | EC2 instance type for ECS container instances   | `string`       | `"t2.micro"` |    no    |
| min_size         | Minimum size of EC2 Auto Scaling Group          | `number`       | `1`          |    no    |
| max_size         | Maximum size of EC2 Auto Scaling Group          | `number`       | `1`          |    no    |
| desired_capacity | Desired capacity of EC2 Auto Scaling Group      | `number`       | `1`          |    no    |

## Outputs

| Name                    | Description                           |
| ----------------------- | ------------------------------------- |
| cluster_id              | ID of the ECS Cluster                 |
| cluster_arn             | ARN of the ECS Cluster                |
| cluster_name            | Name of the ECS Cluster               |
| autoscaling_group_name  | Name of the autoscaling group for ECS |
| security_group_id       | ID of the security group for ECS      |
| task_execution_role_arn | ARN of ECS task execution role        |

## Notes

- Uses the latest Amazon Linux 2 ECS-optimized AMI
- Implements debug logging to help troubleshoot issues
- Auto-scaling group is protected from scale-in to prevent disruption to running tasks
