# Fetch database credentials from AWS Secrets Manager
data "aws_secretsmanager_secret" "db_creds" {
  name = "${var.infra_env}/db_creds"
}

data "aws_secretsmanager_secret_version" "db_creds" {
  secret_id = data.aws_secretsmanager_secret.db_creds.id
}

locals {
  db_creds = jsondecode(data.aws_secretsmanager_secret_version.db_creds.secret_string)
}

# Use the RDS module instead of individual resources
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0" # Use latest 6.x version

  identifier = "${var.name}-db"

  # Engine settings
  engine               = "postgres"
  family               = "postgres14"
  major_engine_version = "14"
  instance_class       = "db.t3.micro"

  # Storage settings
  allocated_storage     = 20
  max_allocated_storage = 20
  storage_encrypted     = false

  # Database credentials from Secrets Manager
  db_name                     = var.org
  manage_master_user_password = false
  username                    = local.db_creds.db_username
  password                    = local.db_creds.db_password
  port                        = 5432

  # Network settings
  vpc_security_group_ids = [aws_security_group.db.id]
  subnet_ids             = var.public_subnets
  create_db_subnet_group = true
  db_subnet_group_name   = "${var.org}-${var.infra_env}-public-db-subnet-group"
  publicly_accessible    = true

  # Maintenance settings
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  # Use default parameter group
  create_db_parameter_group = false
  parameter_group_name      = "default.postgres17"

  # Tags
  tags = {
    Name        = "UnifyOps Database"
    Environment = "Development"
  }
}
