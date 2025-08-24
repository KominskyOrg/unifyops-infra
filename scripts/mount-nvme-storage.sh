#!/bin/bash
set -e

echo "🔧 Setting up 3.6TB NVMe Storage for Longhorn"
echo "============================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
NVME_DEVICE="/dev/nvme0n1p1"
MOUNT_POINT="/var/lib/longhorn"

echo ""
echo "Storage Device: $NVME_DEVICE (3.6TB)"
echo "Mount Point: $MOUNT_POINT"
echo ""

# Check if device exists
if [ ! -b "$NVME_DEVICE" ]; then
    echo -e "${RED}Error: Device $NVME_DEVICE not found!${NC}"
    exit 1
fi

# Create mount point
echo "Creating mount point..."
sudo mkdir -p "$MOUNT_POINT"

# Check if already mounted
if mount | grep -q "$MOUNT_POINT"; then
    echo -e "${YELLOW}Warning: $MOUNT_POINT is already mounted${NC}"
    mount | grep "$MOUNT_POINT"
    echo "Unmounting first..."
    sudo umount "$MOUNT_POINT"
fi

# Mount the NVMe drive
echo "Mounting NVMe drive..."
sudo mount "$NVME_DEVICE" "$MOUNT_POINT"

# Set permissions
echo "Setting permissions..."
sudo chmod 755 "$MOUNT_POINT"

# Get UUID for fstab
UUID=$(sudo blkid -s UUID -o value "$NVME_DEVICE")
echo -e "${GREEN}Drive UUID: $UUID${NC}"

# Check if already in fstab
if grep -q "$UUID" /etc/fstab; then
    echo -e "${YELLOW}UUID already in /etc/fstab${NC}"
else
    echo "Adding to /etc/fstab for persistent mounting..."
    echo "# Longhorn storage - 3.6TB NVMe" | sudo tee -a /etc/fstab
    echo "UUID=$UUID $MOUNT_POINT ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
    echo -e "${GREEN}✓ Added to /etc/fstab${NC}"
fi

# Verify mount
echo ""
echo "Verifying mount..."
df -h "$MOUNT_POINT"

# Create Longhorn directories
echo ""
echo "Creating Longhorn directories..."
sudo mkdir -p "$MOUNT_POINT/replicas"
sudo chmod 755 "$MOUNT_POINT/replicas"

echo ""
echo -e "${GREEN}✅ NVMe storage setup complete!${NC}"
echo ""
echo "Storage summary:"
echo "  Device: $NVME_DEVICE"
echo "  Mount: $MOUNT_POINT"
echo "  Size: $(df -h "$MOUNT_POINT" | tail -1 | awk '{print $2}')"
echo "  Available: $(df -h "$MOUNT_POINT" | tail -1 | awk '{print $4}')"
echo ""
echo "Next steps:"
echo "1. Delete the failed Longhorn app in ArgoCD"
echo "2. Push the updated configuration: git push origin main"
echo "3. Reapply Longhorn: kubectl apply -f clusters/unifyops-home/apps/longhorn.yaml"