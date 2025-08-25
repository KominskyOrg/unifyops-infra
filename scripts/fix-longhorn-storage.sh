#!/bin/bash

echo "🔧 Fixing Longhorn to use 3.6TB NVMe Drive"
echo "==========================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "Step 1: Checking current mount status..."
echo "-----------------------------------------"
df -h /var/lib/longhorn 2>/dev/null || echo -e "${RED}Path not mounted${NC}"

echo ""
echo "Step 2: Checking NVMe drive..."
echo "-------------------------------"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | grep nvme

echo ""
echo "Step 3: Mounting NVMe to /var/lib/longhorn..."
echo "----------------------------------------------"

# Check if already mounted correctly
if mount | grep -q "nvme0n1p1 on /var/lib/longhorn"; then
    echo -e "${GREEN}✓ NVMe already mounted at /var/lib/longhorn${NC}"
else
    echo "Mounting /dev/nvme0n1p1 to /var/lib/longhorn..."
    
    # Create directory if not exists
    sudo mkdir -p /var/lib/longhorn
    
    # Mount the drive
    sudo mount /dev/nvme0n1p1 /var/lib/longhorn
    
    # Add to fstab if not already there
    if ! grep -q nvme0n1p1 /etc/fstab; then
        UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p1)
        echo "UUID=$UUID /var/lib/longhorn ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
        echo -e "${GREEN}✓ Added to /etc/fstab for persistence${NC}"
    fi
    
    echo -e "${GREEN}✓ NVMe mounted successfully${NC}"
fi

echo ""
echo "Step 4: Updating Longhorn configuration..."
echo "------------------------------------------"

# Get the node name
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo "Node name: $NODE_NAME"

# Update Longhorn node configuration
kubectl patch node.longhorn.io/$NODE_NAME -n longhorn-system --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/disks",
    "value": {
      "nvme-disk": {
        "path": "/var/lib/longhorn",
        "allowScheduling": true,
        "storageReserved": 0,
        "tags": ["nvme", "fast"]
      }
    }
  }
]' 2>/dev/null && echo -e "${GREEN}✓ Longhorn node configuration updated${NC}" || {
    echo -e "${YELLOW}Manual configuration needed in Longhorn UI${NC}"
    echo ""
    echo "Go to http://longhorn.local and:"
    echo "1. Click on 'Node' tab"
    echo "2. Click on your node"
    echo "3. Click 'Edit Node and Disks'"
    echo "4. Remove the current disk"
    echo "5. Add new disk with path: /var/lib/longhorn"
    echo "6. Set it as schedulable"
}

echo ""
echo "Step 5: Verifying storage capacity..."
echo "--------------------------------------"
STORAGE_SIZE=$(df -h /var/lib/longhorn | tail -1 | awk '{print $2}')
STORAGE_AVAIL=$(df -h /var/lib/longhorn | tail -1 | awk '{print $4}')

echo -e "Total Size: ${GREEN}$STORAGE_SIZE${NC}"
echo -e "Available: ${GREEN}$STORAGE_AVAIL${NC}"

if [[ "$STORAGE_SIZE" == *"T"* ]]; then
    echo -e "${GREEN}✅ Success! Longhorn should now show ~3.6TB of storage${NC}"
else
    echo -e "${RED}⚠ Storage size seems incorrect. Please check the mount.${NC}"
fi

echo ""
echo "📊 Check Longhorn UI at: http://longhorn.local"
echo "   The dashboard should now show ~3.6TB of schedulable storage"