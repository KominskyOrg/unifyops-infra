# Keep the security group definition separate
resource "aws_security_group" "db" {
  name        = "unifyops-db-sg"
  description = "Allow traffic from ECS to RDS"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.ecs_cluster.security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.org}-sg-rds"
  }
}

# Use the RDS module instead of individual resources
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0" # Use latest 6.x version

  identifier = var.org

  # Engine settings
  engine               = "postgres"
  family               = "postgres14"
  major_engine_version = "14"
  instance_class       = "db.t3.micro"

  # Storage settings
  allocated_storage     = 20
  max_allocated_storage = 20
  storage_encrypted     = false

  # Database credentials
  db_name  = var.org
  username = "postgres"
  password = var.db_password
  port     = 5432

  # Network settings
  vpc_security_group_ids = [aws_security_group.db.id]
  subnet_ids             = module.vpc.private_subnets
  create_db_subnet_group = true
  db_subnet_group_name   = "unifyops-db-subnet-group"
  publicly_accessible    = false

  # Maintenance settings
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = false

  # Use default parameter group
  create_db_parameter_group = false
  parameter_group_name      = "default.postgres17"

  # Tags
  tags = {
    Name        = "UnifyOps Database"
    Environment = "Development"
  }
}

# Keep the secrets management separate
resource "aws_secretsmanager_secret" "db_url" {
  name = "unifyops/db-url"
}

resource "aws_secretsmanager_secret_version" "db_url" {
  secret_id     = aws_secretsmanager_secret.db_url.id
  secret_string = "postgresql://${module.db.db_instance_username}:${var.db_password}@${module.db.db_instance_endpoint}/${module.db.db_instance_name}"
}
