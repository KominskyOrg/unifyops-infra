# EC2 Instance using terraform-aws-ec2-instance module with built-in hardening
module "web_server" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 5.0"

  name = "${local.name}-web-server"

  ami                         = "ami-08b5b3a93ed654d19"
  instance_type               = var.instance_type
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.ssh.id, aws_security_group.web.id]
  associate_public_ip_address = true
  key_name                    = "unifyops-key"
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  monitoring                  = true

  # User data for hardening - templatefile() reads the script from a file and passes variables to it
  user_data = templatefile("${path.module}/../scripts/os_hardening/ec2_user_data_hardening.sh", {
    org          = var.org,
    project_name = var.project_name
  })
  user_data_replace_on_change = true

  root_block_device = [
    {
      volume_size = 10
      volume_type = "gp3"
      encrypted   = true
    }
  ]

  tags = merge(
    local.tags,
    {
      Role            = "Web Server"
      SecurityProfile = "Hardened"
    }
  )
}

# CloudWatch Logs for security monitoring
resource "aws_cloudwatch_log_group" "security_logs" {
  for_each = toset([
    "/var/log/secure",
    "/var/log/fail2ban.log",
    "/var/log/user-data.log"
  ])

  name              = "${var.org}-${var.project_name}${each.key}"
  retention_in_days = 30

  tags = local.tags
}

# CloudWatch Dashboard for security monitoring
resource "aws_cloudwatch_dashboard" "security_dashboard" {
  dashboard_name = "${local.name}-security-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "log"
        x      = 0
        y      = 0
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '${var.org}-${var.project_name}/var/log/secure' | fields @timestamp, @message | filter @message like /Failed password/ | stats count(*) as failedLogins by bin(1h)"
          region = var.region
          title  = "Failed Login Attempts"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '${var.org}-${var.project_name}/var/log/fail2ban.log' | fields @timestamp, @message | filter @message like /Ban/ | stats count(*) as bannedIPs by bin(1h)"
          region = var.region
          title  = "Fail2Ban Activity"
        }
      }
    ]
  })
}

# Parameter for admin username (if you want to make it configurable)
variable "admin_username" {
  description = "Username for the non-root admin user"
  type        = string
  default     = "unifyops-admin"
}

# Create an AWS parameter to store the admin username 
# This can be used by other processes that need to know the admin user
resource "aws_ssm_parameter" "admin_username" {
  name  = "/${local.name}/admin-username"
  type  = "String"
  value = var.admin_username

  tags = local.tags
}

# Outputs for EC2 Instance
output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = module.web_server.public_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = module.web_server.public_dns
}
