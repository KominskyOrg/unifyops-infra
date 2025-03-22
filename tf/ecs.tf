# ECS cluster configuration using terraform-aws-modules
# =================================================

module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 5.12.0" # Using the latest stable version

  cluster_name = "${local.name}-cluster"

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
        cloud_watch_log_group_name     = "/ecs/${local.name}"
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

  # Service definitions will be created in the application module
  # using the exported cluster ARN/ID/name

  # Set up the task execution role (for pulling ECR images, logs)
  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "${local.name}-task-exec-role"

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

  tags = local.tags
}

# CloudWatch log group for ECS tasks (maintained for compatibility with existing resources)
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${local.name}"
  retention_in_days = 30
  tags              = local.tags
}

# Networking and security
# ======================

# Security Group for ECS
resource "aws_security_group" "ecs_sg" {
  name        = "${local.name}-ecs-sg"
  description = "Security group for ECS"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 8000
    to_port     = 8000
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
      Name = "${local.name}-ecs-sg"
    }
  )
}

# Auto Scaling Group for ECS (Free Tier)
# =====================================

# Launch Template for ECS instances
resource "aws_launch_template" "ecs_lt" {
  name                   = "${local.name}-ecs-lt"
  image_id               = "ami-0c7217cdde317cfec" # Amazon Linux 2 ECS optimized AMI for us-east-1
  instance_type          = "t2.micro"              # Free tier eligible
  vpc_security_group_ids = [aws_security_group.ecs_sg.id]
  key_name               = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${module.ecs.cluster_name} >> /etc/ecs/ecs.config
    echo ECS_LOGLEVEL=debug >> /etc/ecs/ecs.config
    echo ECS_AVAILABLE_LOGGING_DRIVERS='["json-file","awslogs"]' >> /etc/ecs/ecs.config
    
    # Update and restart ECS agent
    yum install -y aws-cli jq
    yum update -y ecs-init
    systemctl restart ecs
    
    # Log the result for troubleshooting
    echo "ECS agent configuration completed" >> /var/log/user-data.log
    systemctl status ecs >> /var/log/user-data.log
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.tags,
      {
        Name = "${local.name}-ecs-instance"
      }
    )
  }
}

# Auto Scaling Group for ECS instances
resource "aws_autoscaling_group" "ecs_asg" {
  name                = "${local.name}-ecs-asg"
  vpc_zone_identifier = module.vpc.public_subnets
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1

  launch_template {
    id      = aws_launch_template.ecs_lt.id
    version = "$Latest"
  }

  protect_from_scale_in = true

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# IAM Role and Instance Profile for ECS Instances
resource "aws_iam_role" "ecs_instance_role" {
  name = "${local.name}-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role_attachment" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
