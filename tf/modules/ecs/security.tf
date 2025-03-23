# Security Group for ECS
resource "aws_security_group" "ecs_sg" {
  name        = "${var.name}-ecs-sg"
  description = "Security group for ECS"
  vpc_id      = var.vpc_id

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
    var.tags,
    {
      Name = "${var.name}-ecs-sg"
    }
  )
} 
