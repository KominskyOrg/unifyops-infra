#!/bin/bash
set -e

echo "🔍 Checking Storage Configuration for Longhorn"
echo "=============================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check current disk configuration
echo "📊 Current Disk Configuration:"
echo "------------------------------"
lsblk
echo ""

echo "💾 Disk Usage:"
echo "--------------"
df -h
echo ""

# Check if Longhorn directory exists
LONGHORN_PATH="/var/lib/longhorn"
echo "🔍 Checking Longhorn data path: $LONGHORN_PATH"

if [ -d "$LONGHORN_PATH" ]; then
    echo -e "${GREEN}✓ Directory exists${NC}"
    
    # Check mount point
    MOUNT_INFO=$(df -h "$LONGHORN_PATH" | tail -1)
    echo "  Mount info: $MOUNT_INFO"
    
    # Check available space
    AVAIL_SPACE=$(df -h "$LONGHORN_PATH" | tail -1 | awk '{print $4}')
    echo -e "  Available space: ${GREEN}$AVAIL_SPACE${NC}"
    
    # Check if it's on a separate disk (not root)
    ROOT_DEVICE=$(df / | tail -1 | awk '{print $1}')
    LONGHORN_DEVICE=$(df "$LONGHORN_PATH" | tail -1 | awk '{print $1}')
    
    if [ "$ROOT_DEVICE" == "$LONGHORN_DEVICE" ]; then
        echo -e "${YELLOW}⚠ WARNING: Longhorn path is on the same device as root filesystem${NC}"
        echo -e "${YELLOW}  Consider mounting your 4TB SSD to $LONGHORN_PATH${NC}"
    else
        echo -e "${GREEN}✓ Longhorn path is on a separate device from root${NC}"
    fi
else
    echo -e "${RED}✗ Directory does not exist${NC}"
    echo ""
    echo "To set up your 4TB SSD for Longhorn:"
    echo "1. Identify your 4TB disk with: lsblk"
    echo "2. Create and mount it:"
    echo "   sudo mkdir -p $LONGHORN_PATH"
    echo "   sudo mount /dev/sdX1 $LONGHORN_PATH  # Replace sdX1 with your disk"
    echo "3. Add to /etc/fstab for permanent mounting"
fi

echo ""
echo "📝 Recommendations:"
echo "-------------------"
echo "1. Use your 4TB SSD exclusively for Kubernetes storage"
echo "2. Mount it at $LONGHORN_PATH (or update apps/longhorn/values.yaml)"
echo "3. Ensure the mount is persistent via /etc/fstab"
echo "4. Keep at least 10% free space for optimal performance"
echo ""
echo "After setup, commit and push changes, then sync Longhorn in ArgoCD"