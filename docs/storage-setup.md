# Storage Configuration for Kubernetes

## Disk Layout
- **1TB SSD**: OS and system storage (/)
- **4TB SSD**: Dedicated Kubernetes persistent storage

## Setting Up the 4TB SSD for Longhorn

### 1. First, SSH into your server and identify the 4TB disk:

```bash
# List all block devices
lsblk

# Show disk usage
df -h

# List disks with more detail
sudo fdisk -l
```

### 2. Format and mount the 4TB disk (if not already done):

```bash
# Assuming the 4TB disk is /dev/sdb (verify with lsblk!)
# Create a partition (if needed)
sudo fdisk /dev/sdb
# Press: n (new), p (primary), 1 (partition 1), Enter, Enter, w (write)

# Format with ext4
sudo mkfs.ext4 /dev/sdb1

# Create mount point
sudo mkdir -p /var/lib/longhorn

# Mount the disk
sudo mount /dev/sdb1 /var/lib/longhorn

# Add to /etc/fstab for permanent mounting
echo '/dev/sdb1 /var/lib/longhorn ext4 defaults 0 2' | sudo tee -a /etc/fstab

# Verify mount
df -h /var/lib/longhorn
```

### 3. Set correct permissions:

```bash
# Longhorn needs write access
sudo chmod 755 /var/lib/longhorn
```

## Alternative Mount Points

If you prefer a different location or the disk is already mounted elsewhere:

```bash
# For example, if mounted at /mnt/storage
sudo mkdir -p /mnt/storage/longhorn
# Update Longhorn configuration to use /mnt/storage/longhorn
```

## Verifying Longhorn is Using the Correct Disk

After Longhorn is deployed:

1. Access Longhorn UI (usually at http://<node-ip>:30000 or via Ingress)
2. Go to Node tab
3. Check the "Data Path" for your node
4. Verify it shows your 4TB mount point

## Monitoring Disk Usage

```bash
# Check Longhorn storage usage
df -h /var/lib/longhorn

# Check all Longhorn volumes
kubectl get pv

# Check disk I/O
iostat -x 1
```

## Important Notes

- **Never** use the OS disk (1TB) for Longhorn data to avoid filling up the system disk
- Longhorn will automatically manage the storage within the path you specify
- Regular backups to external storage (S3/NFS) are recommended for critical data