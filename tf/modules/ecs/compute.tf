# Launch Template for ECS instances
resource "aws_launch_template" "ecs_lt" {
  name          = "${var.name}-ecs-lt"
  image_id      = "ami-07bd539d6a69884fb" # Latest Amazon Linux 2 ECS optimized AMI for us-east-1 (as of March 2025)
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -ex

    # Install required packages
    echo "Installing required packages..."
    yum update -y
    
    # Enable and install ECS from the extras repository
    echo "Setting up ECS repository and installing amazon-ecs-init..."
    amazon-linux-extras enable ecs
    yum install -y amazon-ecs-init aws-cli jq curl docker
    
    # Verify ECS binary exists
    if [ ! -f /usr/libexec/amazon-ecs-init ]; then
      echo "ERROR: amazon-ecs-init binary not found after installation. Trying alternative installation..."
      
      # Alternative installation method for amazon-ecs-init
      yum clean all
      yum makecache fast
      yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
      amazon-linux-extras list | grep -i ecs
      amazon-linux-extras install -y ecs
      
      # Check again
      if [ ! -f /usr/libexec/amazon-ecs-init ]; then
        echo "CRITICAL: Still unable to find amazon-ecs-init binary. Manual intervention required."
        # Create a flag file to indicate this issue
        echo "Missing amazon-ecs-init binary" > /var/log/ecs-init-missing
      fi
    fi

    # Ensure networking is up
    echo "Checking network connectivity..."
    RETRY_COUNT=0
    MAX_RETRIES=10
    until curl -s --connect-timeout 5 https://ecs.us-east-1.amazonaws.com > /dev/null || [ $RETRY_COUNT -eq $MAX_RETRIES ]; do
      echo "Waiting for network connectivity... ($RETRY_COUNT/$MAX_RETRIES)"
      sleep 5
      RETRY_COUNT=$((RETRY_COUNT+1))
    done

    # Ensure Docker is running
    echo "Starting Docker service..."
    systemctl enable docker
    systemctl start docker
    # Wait for Docker to be fully available
    timeout 60 bash -c 'until docker info &>/dev/null; do sleep 1; done'
    
    # Configure ECS agent before starting it
    echo "Configuring ECS agent..."
    mkdir -p /etc/ecs
    cat > /etc/ecs/ecs.config << ECSCONF
    ECS_CLUSTER=${var.name}-cluster
    ECS_LOGLEVEL=debug
    ECS_AVAILABLE_LOGGING_DRIVERS=["json-file","awslogs"]
    ECS_ENABLE_CONTAINER_METADATA=true
    ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION=1h
    ECSCONF

    # Pull the latest ECS agent image to ensure it exists
    echo "Pulling ECS agent Docker image..."
    docker pull amazon/amazon-ecs-agent:latest

    # Start and enable the ECS service
    echo "Starting and enabling ECS service..."
    
    # Check if the ecs.service file exists
    if [ -f /usr/lib/systemd/system/ecs.service ]; then
      systemctl enable ecs
      systemctl start ecs
    else
      echo "ECS service file not found. Creating a custom service file..."
      
      # Create a custom ecs.service file
      cat > /etc/systemd/system/ecs.service << 'ECSSERVICE'
[Unit]
Description=Amazon Elastic Container Service - container agent
Documentation=https://aws.amazon.com/documentation/ecs/
Requires=docker.service
After=docker.service

[Service]
Type=simple
Restart=on-failure
RestartSec=10
ExecStartPre=/usr/libexec/amazon-ecs-init pre-start
ExecStart=/usr/libexec/amazon-ecs-init start
ExecStop=/usr/libexec/amazon-ecs-init stop
ExecStopPost=/usr/libexec/amazon-ecs-init post-stop

[Install]
WantedBy=multi-user.target
ECSSERVICE

      # Reload systemd and start the service
      systemctl daemon-reload
      systemctl enable ecs
      systemctl start ecs
    fi

    # Give the service time to fully initialize
    sleep 5

    # Verify ECS agent is running and retry if needed
    echo "Verifying ECS agent status..."
    if ! systemctl is-active ecs; then
      echo "ECS service not running, attempting manual recovery..."
      # Try to run the ECS agent directly
      /usr/libexec/amazon-ecs-init start
      
      # Check if ECS container is running
      if ! docker ps | grep -q amazon-ecs-agent; then
        echo "ECS agent container not running, trying alternative approach..."
        docker stop ecs-agent || true
        docker rm ecs-agent || true
        docker run --name ecs-agent \
          --detach=true \
          --restart=on-failure:10 \
          --volume=/var/run:/var/run \
          --volume=/var/log/ecs/:/log \
          --volume=/var/lib/ecs/data:/data \
          --volume=/etc/ecs:/etc/ecs \
          --volume=/etc/ecs:/etc/ecs/pki \
          --net=host \
          --env-file=/etc/ecs/ecs.config \
          amazon/amazon-ecs-agent:latest
      fi
    fi

    # Verify ECS agent is registered with the cluster
    echo "Checking ECS agent registration..."
    CONTAINER_INSTANCE_ID=$(curl -s 169.254.169.254/latest/meta-data/instance-id)
    aws ecs list-container-instances --cluster ${var.name}-cluster --region us-east-1 | grep -q $CONTAINER_INSTANCE_ID || echo "Warning: Instance not registered with cluster"

    # Check network connectivity
    echo "Checking network connectivity..."
    curl -s --connect-timeout 5 https://ecs.us-east-1.amazonaws.com || echo "Warning: Cannot reach ECS service"
    curl -s --connect-timeout 5 https://ecr.us-east-1.amazonaws.com || echo "Warning: Cannot reach ECR service"
    
    # Add debugging information
    echo "==== ECS Agent Installation Debug Info ====" > /var/log/ecs-install.log
    echo "Date: $(date)" >> /var/log/ecs-install.log
    echo "Instance ID: $(curl -s 169.254.169.254/latest/meta-data/instance-id)" >> /var/log/ecs-install.log
    echo "Amazon ECS Init package status:" >> /var/log/ecs-install.log
    rpm -qa | grep amazon-ecs-init >> /var/log/ecs-install.log
    echo "Docker status:" >> /var/log/ecs-install.log
    systemctl status docker >> /var/log/ecs-install.log 2>&1
    echo "ECS service status:" >> /var/log/ecs-install.log
    systemctl status ecs >> /var/log/ecs-install.log 2>&1
    echo "ECS config file:" >> /var/log/ecs-install.log
    cat /etc/ecs/ecs.config >> /var/log/ecs-install.log
    echo "Running containers:" >> /var/log/ecs-install.log
    docker ps -a >> /var/log/ecs-install.log 2>&1
    echo "Docker logs for ECS agent:" >> /var/log/ecs-install.log
    docker logs ecs-agent >> /var/log/ecs-install.log 2>&1 || echo "No ecs-agent container logs available" >> /var/log/ecs-install.log
    echo "Network connectivity test:" >> /var/log/ecs-install.log
    curl -v https://ecs.us-east-1.amazonaws.com >> /var/log/ecs-install.log 2>&1 || echo "Failed to connect to ECS endpoint" >> /var/log/ecs-install.log
    curl -v https://ecr.us-east-1.amazonaws.com >> /var/log/ecs-install.log 2>&1 || echo "Failed to connect to ECR endpoint" >> /var/log/ecs-install.log
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

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ecs_sg.id, aws_security_group.ssh.id, aws_security_group.web.id]
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
