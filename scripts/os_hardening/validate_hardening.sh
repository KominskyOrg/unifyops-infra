#!/bin/bash
# EC2 Hardening Validation Script
# This script verifies that security hardening measures have been properly implemented
# Author: UnifyOps Team
# Date: $(date +"%Y-%m-%d")

echo "===== EC2 Hardening Validation ====="
echo "Running checks to verify security hardening measures..."

# Function to check if a service is active
check_service() {
  if systemctl is-active --quiet $1; then
    echo "✅ $1 is active and running"
    return 0
  else
    echo "❌ $1 is NOT active"
    return 1
  fi
}

# Function to check package installation
check_package() {
  if rpm -q $1 &>/dev/null; then
    echo "✅ $1 is installed"
    return 0
  else
    echo "❌ $1 is NOT installed"
    return 1
  fi
}

# Check if system is up to date
echo -e "\n== Checking system updates =="
yum check-update --security 2>/dev/null
if [ $? -eq 0 ]; then
  echo "✅ System is up to date"
else
  echo "❌ System has pending security updates"
fi

# Check SSH configuration
echo -e "\n== Checking SSH configuration =="
SSH_CONFIG_CHECKS=(
  "PermitRootLogin no"
  "PasswordAuthentication no"
  "PermitEmptyPasswords no"
  "PubkeyAuthentication yes"
  "X11Forwarding no"
)

for check in "${SSH_CONFIG_CHECKS[@]}"; do
  if sudo grep -q "^${check}" /etc/ssh/sshd_config; then
    echo "✅ SSH: ${check}"
  else
    echo "❌ SSH configuration issue: ${check} not set"
  fi
done

# Check firewall configuration
echo -e "\n== Checking firewall configuration =="
check_service firewalld

echo "Firewall rules:"
sudo firewall-cmd --list-all

# Check SSH port is the only one open other than HTTP/HTTPS
OPEN_PORTS=$(sudo firewall-cmd --zone=public --list-ports)
OPEN_SERVICES=$(sudo firewall-cmd --zone=public --list-services)

echo "Open ports: $OPEN_PORTS"
echo "Open services: $OPEN_SERVICES"

if [[ "$OPEN_SERVICES" =~ ssh ]] && [[ "$OPEN_SERVICES" =~ http ]] && [[ "$OPEN_SERVICES" =~ https ]]; then
  echo "✅ Firewall allows only necessary services (SSH, HTTP, HTTPS)"
else
  echo "❌ Firewall configuration needs review"
fi

# Check fail2ban
echo -e "\n== Checking fail2ban configuration =="
check_package fail2ban
check_service fail2ban

if [ -f /etc/fail2ban/jail.d/sshd.local ]; then
  echo "✅ fail2ban SSH jail is configured"
else
  echo "❌ fail2ban SSH jail is not configured"
fi

# Check non-root sudo users
echo -e "\n== Checking for non-root sudo users =="
SUDO_USERS=$(grep -Po '^sudo.+:\K.*$' /etc/group | tr ',' '\n' | grep -v "root")
if [ -n "$SUDO_USERS" ]; then
  echo "✅ Non-root sudo users exist: $SUDO_USERS"
else
  SUDOERS_FILES=$(ls /etc/sudoers.d/ 2>/dev/null)
  if [ -n "$SUDOERS_FILES" ]; then
    echo "✅ Custom sudoers files exist: $SUDOERS_FILES"
  else
    echo "❌ No non-root sudo users found"
  fi
fi

# Check password policies
echo -e "\n== Checking password policies =="
if grep -q "minlen=12" /etc/pam.d/system-auth; then
  echo "✅ Strong password policy is configured"
else
  echo "❌ Password policy needs review"
fi

# Check file permissions
echo -e "\n== Checking system file permissions =="
SYSTEM_FILES=(
  "/etc/passwd"
  "/etc/shadow"
  "/etc/gshadow"
  "/etc/group"
)

for file in "${SYSTEM_FILES[@]}"; do
  PERMS=$(stat -c "%a" $file)
  if [ "$PERMS" -le "644" ]; then
    echo "✅ $file has secure permissions: $PERMS"
  else
    echo "❌ $file has insecure permissions: $PERMS"
  fi
done

# Check shared memory configuration
echo -e "\n== Checking shared memory configuration =="
if grep -q "tmpfs.*\/dev\/shm.*noexec" /etc/fstab; then
  echo "✅ Shared memory is configured securely"
else
  echo "❌ Shared memory configuration needs review"
fi

# Check crypto policies
echo -e "\n== Checking crypto policies =="
if [ -f /etc/crypto-policies/config ]; then
  CRYPTO_POLICY=$(cat /etc/crypto-policies/config)
  echo "Current crypto policy: $CRYPTO_POLICY"
  if [[ "$CRYPTO_POLICY" == "DEFAULT:NO-SHA1" ]]; then
    echo "✅ Strong crypto policy is configured"
  else
    echo "❌ Crypto policy needs review"
  fi
else
  echo "❌ Crypto policies not found"
fi

echo -e "\n===== Validation Complete ====="
echo "Review the output above to ensure all security measures are properly implemented."
echo "Address any items marked with ❌ to improve your security posture." 