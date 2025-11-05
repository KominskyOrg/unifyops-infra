# Setup Instructions for Building Custom Runner Image

## Prerequisites

### 1. Docker Registry Authentication

You need to authenticate with both registries:

#### GitHub Container Registry (for pulling base image)
```bash
# Create a GitHub Personal Access Token (PAT) with read:packages scope
# Go to: https://github.com/settings/tokens
# Create token with 'read:packages' permission

# Login to GitHub Container Registry
echo "YOUR_GITHUB_PAT" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

#### Harbor Registry (for pushing custom image)
```bash
# Login to Harbor
docker login harbor.unifyops.io
# Username: (your Harbor username or robot account)
# Password: (your Harbor password or robot token)
```

### 2. Verify Authentication

```bash
# Check Docker credentials
cat ~/.docker/config.json

# Should show both registries:
# {
#   "auths": {
#     "ghcr.io": {...},
#     "harbor.unifyops.io": {...}
#   }
# }
```

## Building the Image

Once authenticated to both registries:

```bash
# Build and push to Harbor
./build.sh --push

# Or build with custom tag
./build.sh --tag v1.0.0 --push
```

## Alternative: Use Public Base Image

If you don't want to authenticate with GitHub, you can modify the Dockerfile to use a public runner image or build from Ubuntu:

```dockerfile
# Option 1: Public Ubuntu-based build (requires more setup)
FROM ubuntu:22.04

# Install GitHub Actions runner manually
# ... (more complex)

# Option 2: Check if there's a public mirror
FROM ghcr.io/actions/actions-runner:latest
```

## Creating Harbor Robot Account (Recommended)

For production use, create a dedicated robot account in Harbor:

1. Login to Harbor UI: https://harbor.unifyops.io
2. Navigate to: Projects → library → Robot Accounts
3. Click "New Robot Account"
4. Name: `arc-runner`
5. Permissions:
   - ✅ Pull artifacts (for pulling images in runners)
   - ✅ Push artifacts (for pushing the custom runner image)
6. Click "Add" and copy the token
7. Use these credentials:
   - Username: `robot$arc-runner`
   - Password: `<the token you copied>`

### Using Robot Account

```bash
# Login with robot account
docker login harbor.unifyops.io -u 'robot$arc-runner' -p 'YOUR_ROBOT_TOKEN'

# Or use environment variable
export HARBOR_ROBOT_TOKEN='YOUR_ROBOT_TOKEN'
echo "$HARBOR_ROBOT_TOKEN" | docker login harbor.unifyops.io -u 'robot$arc-runner' --password-stdin
```

## Kubernetes Secret for Image Pulling

After building and pushing the image, create the Kubernetes secret:

```bash
# Using robot account (recommended)
kubectl create secret docker-registry harbor-registry-secret \
  --namespace=github-runners \
  --docker-server=harbor.unifyops.io \
  --docker-username='robot$arc-runner' \
  --docker-password='YOUR_ROBOT_TOKEN'

# Verify secret
kubectl get secret harbor-registry-secret -n github-runners
```

## Troubleshooting

### "denied: denied" error when building
**Cause**: Not authenticated to ghcr.io
**Solution**: Login to GitHub Container Registry (see step 1 above)

### "unauthorized: authentication required" when pushing
**Cause**: Not authenticated to Harbor
**Solution**: Login to Harbor registry

### Can't login to ghcr.io
**Cause**: Invalid or missing GitHub PAT
**Solution**: Create new PAT with `read:packages` scope

### Docker login credentials not persisting
**Cause**: Credential helpers or Docker Desktop issues
**Solution**:
```bash
# Check credential store
docker-credential-desktop list

# Or manually edit ~/.docker/config.json
```
