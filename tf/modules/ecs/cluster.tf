# ECS cluster configuration using terraform-aws-modules
module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 5.12.0"

  cluster_name = "${var.name}-cluster"

  # Enable CloudWatch container insights
  cluster_settings = {
    name  = "containerInsights"
    value = "enabled"
  }

  # Always use EC2 launch type for free tier eligibility
  default_capacity_provider_use_fargate = false

  # CloudWatch logs integration
  cluster_configuration = {
    execute_command_configuration = {
      logging = "OVERRIDE"
      log_configuration = {
        cloud_watch_log_group_name     = "/ecs/${var.name}"
        cloud_watch_encryption_enabled = false
      }
    }
  }

  # Auto scaling group configuration for EC2 instances (free tier)
  autoscaling_capacity_providers = {
    custom-ec2 = {
      auto_scaling_group_arn         = aws_autoscaling_group.ecs_asg.arn
      managed_termination_protection = "ENABLED"

      managed_scaling = {
        maximum_scaling_step_size = 1
        minimum_scaling_step_size = 1
        status                    = "ENABLED"
        target_capacity           = 100
      }

      default_capacity_provider_strategy = {
        weight = 100
      }
    }
  }

  # Set up the task execution role (for pulling ECR images, logs)
  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "${var.name}-task-exec-role"

  # Add permissions to access ECR and CloudWatch logs
  task_exec_iam_statements = {
    ecr = {
      effect = "Allow",
      actions = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      resources = ["*"]
    },
    logs = {
      effect = "Allow",
      actions = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      resources = ["*"]
    }
  }

  tags = var.tags
}

# CloudWatch log group for ECS tasks
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.name}"
  retention_in_days = 30
  tags              = var.tags
}
