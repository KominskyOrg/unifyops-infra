#!/bin/bash
# EC2 Hardening User Data Script for Amazon Linux 2
# This script implements the hardening measures specified in DEVOPS-102
# Author: UnifyOps Team
# Date: $(date +"%Y-%m-%d")

# Set script to log output to console for CloudWatch Logs access
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Get variables passed from terraform
ORG="${org}"
PROJECT_NAME="${project_name}"

echo "Starting EC2 hardening process for $ORG-$PROJECT_NAME..."

# 1. Update the system
echo "Updating the system packages..."
yum update -y

# 2. Install required security packages
echo "Installing security packages..."
yum install -y firewalld fail2ban audispd-plugins

# 3. Configure SSH to enforce key-only authentication
echo "Configuring SSH for key-only authentication..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
cat > /etc/ssh/sshd_config << 'EOF'
# Security hardened sshd_config
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
SyslogFacility AUTHPRIV
LogLevel INFO

# Authentication settings
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
AuthenticationMethods publickey

# Other security settings
X11Forwarding no
PrintMotd no
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
LoginGraceTime 60
StrictModes yes

# Accept locale-related environment variables
AcceptEnv LANG LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES
AcceptEnv LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT
AcceptEnv LC_IDENTIFICATION LC_ALL LANGUAGE
AcceptEnv XMODIFIERS

# Override settings in /etc/sshd_config.d/*.conf
Include /etc/ssh/sshd_config.d/*.conf

# Subsystem settings
Subsystem sftp  /usr/libexec/openssh/sftp-server
EOF

# 4. Configure firewalld to restrict ports
echo "Configuring firewall..."
systemctl enable firewalld
systemctl start firewalld
firewall-cmd --permanent --zone=public --remove-service=dhcpv6-client
firewall-cmd --permanent --zone=public --add-service=ssh
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --permanent --zone=public --add-service=https
firewall-cmd --reload

# 5. Set up fail2ban to protect against brute force attacks
echo "Configuring fail2ban..."
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
mkdir -p /etc/fail2ban/jail.d/
cat > /etc/fail2ban/jail.d/sshd.local << 'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/secure
maxretry = 3
bantime = 3600
findtime = 600
EOF
systemctl enable fail2ban
systemctl start fail2ban

# 6. Create a non-root user with sudo privileges
# Define admin user variables - can be parameterized through CloudFormation/Terraform
ADMIN_USER="unifyops-admin"
echo "Creating secure non-root user: $ADMIN_USER"
useradd -m -s /bin/bash "$ADMIN_USER"
mkdir -p /home/"$ADMIN_USER"/.ssh

# Copy the SSH key from the current user to the new user
if [ -f /home/ec2-user/.ssh/authorized_keys ]; then
    cp /home/ec2-user/.ssh/authorized_keys /home/"$ADMIN_USER"/.ssh/
    chown -R "$ADMIN_USER":"$ADMIN_USER" /home/"$ADMIN_USER"/.ssh
    chmod 600 /home/"$ADMIN_USER"/.ssh/authorized_keys
fi

# Add the new user to sudoers
echo "Adding user to sudoers..."
echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$ADMIN_USER"
chmod 440 /etc/sudoers.d/"$ADMIN_USER"

# 7. Configure additional security settings

# 7.1 Secure shared memory
echo "Securing shared memory..."
echo "tmpfs     /dev/shm     tmpfs     defaults,noexec,nosuid     0     0" >> /etc/fstab

# 7.2 Enable strong crypto for system-wide policies
echo "Configuring system-wide crypto policies..."
update-crypto-policies --set DEFAULT:NO-SHA1

# 7.3 Configure password policies
echo "Setting password policies..."
sed -i 's/^password    requisite     pam_pwquality.so.*/password    requisite     pam_pwquality.so try_first_pass local_users_only retry=3 minlen=12 dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1/' /etc/pam.d/system-auth

# 7.4 Set proper file permissions
echo "Setting proper permissions for key system files..."
chmod 600 /etc/passwd
chmod 600 /etc/shadow
chmod 600 /etc/gshadow
chmod 600 /etc/group

# 8. Setup automatic security updates
echo "Configuring automatic security updates..."
yum install -y yum-cron
sed -i 's/apply_updates = no/apply_updates = yes/' /etc/yum/yum-cron.conf
sed -i 's/update_cmd = default/update_cmd = security/' /etc/yum/yum-cron.conf
systemctl enable yum-cron
systemctl start yum-cron

# 9. Setup CloudWatch agent for monitoring security logs
echo "Setting up CloudWatch monitoring..."
yum install -y amazon-cloudwatch-agent

# Create CloudWatch agent configuration with proper variable interpolation
# Escape the {instance_id} to prevent shell expansion
INSTANCE_ID_PLACEHOLDER="{instance_id}"
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/secure",
            "log_group_name": "$ORG-$PROJECT_NAME/var/log/secure",
            "log_stream_name": "$INSTANCE_ID_PLACEHOLDER"
          },
          {
            "file_path": "/var/log/fail2ban.log",
            "log_group_name": "$ORG-$PROJECT_NAME/var/log/fail2ban.log",
            "log_stream_name": "$INSTANCE_ID_PLACEHOLDER"
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "$ORG-$PROJECT_NAME/var/log/user-data.log",
            "log_stream_name": "$INSTANCE_ID_PLACEHOLDER"
          }
        ]
      }
    }
  }
}
EOF
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# 10. Install and configure Nginx for connectivity testing
echo "Installing and configuring Nginx for connectivity testing..."
yum install -y nginx
systemctl enable nginx

# Create a simple hello world page
cat > /usr/share/nginx/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>UnifyOps EC2 Instance</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
            text-align: center;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            border: 1px solid #ddd;
            border-radius: 5px;
            background-color: #f9f9f9;
        }
        h1 {
            color: #333;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Hello World!</h1>
        <p>This UnifyOps EC2 instance is running and accessible.</p>
        <p>Instance hardened on: $(date)</p>
    </div>
</body>
</html>
EOF

# Start Nginx
systemctl start nginx

# 11. Restart services to apply changes
echo "Restarting services to apply changes..."
systemctl restart sshd

# 12. Run validation checks
echo "Running security validation checks..."
SSH_CONFIG_CHECK=$(sshd -T | grep -E "passwordauthentication|permitemptypasswords|permitrootlogin")
echo "SSH Configuration Check:"
echo "$SSH_CONFIG_CHECK"

echo "Firewall Configuration:"
firewall-cmd --list-all

echo "Fail2ban Status:"
fail2ban-client status

# 13. Write validation report
cat > /var/log/hardening_report.txt << EOF
=================================================
EC2 Instance Hardening Report - $(date)
=================================================
- System is up to date
- SSH is configured for key-only authentication
- Root login is disabled
- Firewall is enabled and configured to allow only essential ports
- Fail2ban is active to protect against brute force attacks
- Non-root user ($ADMIN_USER) with sudo privileges created
- Strong password policies enforced
- System file permissions secured
- Automatic security updates enabled
- CloudWatch monitoring configured
- Nginx installed and configured for connectivity testing
=================================================
EOF

echo "Hardening complete! Report available at /var/log/hardening_report.txt" 