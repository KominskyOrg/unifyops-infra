# Launch Template for ECS instances
resource "aws_launch_template" "ecs_lt" {
  name                   = "${var.name}-ecs-lt"
  image_id               = "ami-0c7217cdde317cfec" # Amazon Linux 2 ECS optimized AMI for us-east-1
  instance_type          = var.instance_type
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
      var.tags,
      {
        Name = "${var.name}-ecs-instance"
      }
    )
  }
}

# Auto Scaling Group for ECS instances
resource "aws_autoscaling_group" "ecs_asg" {
  name                = "${var.name}-ecs-asg"
  vpc_zone_identifier = var.public_subnets
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity

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
    for_each = var.tags
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
