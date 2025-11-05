# Custom GitHub Actions Runner Image for UnifyOps

This directory contains a custom GitHub Actions runner image optimized for UnifyOps CI/CD workflows. The image is based on the official GitHub Actions runner and includes pre-installed tools to reduce workflow startup time.

## Features

### Pre-installed Tools
- **yq** (v4.40.5) - YAML processor for updating values files
- **kubectl** (v1.29.1) - Kubernetes CLI for cluster operations
- **helm** (v3.14.0) - Kubernetes package manager
- **git** - Version control
- **jq** - JSON processor
- **curl/wget** - HTTP clients

### Security Best Practices
✅ **Pinned tool versions** - Reproducible builds with specific versions
✅ **SHA256 verification** - All downloaded binaries are verified
✅ **Non-root execution** - Runs as `runner` user (principle of least privilege)
✅ **Minimal packages** - Only essential tools installed with `--no-install-recommends`
✅ **Security hardening** - Removed setuid/setgid permissions
✅ **Health checks** - Container health monitoring
✅ **OCI labels** - Full metadata for image inspection
✅ **Build cache** - Faster rebuilds with BuildKit cache mounts

## Building the Image

### Prerequisites
- Docker with BuildKit enabled
- Access to Harbor registry (`harbor.unifyops.io`)
- Docker login to Harbor: `docker login harbor.unifyops.io`

### Build Commands

```bash
# Basic build
./build.sh

# Build and push to Harbor
./build.sh --push

# Build with custom tag
./build.sh --tag v1.0.0 --push

# Build without cache (for clean builds)
./build.sh --no-cache --push

# Build for specific platform
./build.sh --platform linux/arm64 --push
```

### Manual Build

```bash
# Build the image
docker build -t harbor.unifyops.io/library/arc-runner-unifyops:latest .

# Push to Harbor
docker push harbor.unifyops.io/library/arc-runner-unifyops:latest
```

## Deploying to ARC

### 1. Ensure Harbor Image Pull Secret Exists

The ARC runners need credentials to pull from Harbor. Create a secret if it doesn't exist:

```bash
# Create Harbor pull secret in github-runners namespace
kubectl create secret docker-registry harbor-registry-secret \
  --namespace=github-runners \
  --docker-server=harbor.unifyops.io \
  --docker-username=admin \
  --docker-password='YOUR_HARBOR_PASSWORD' \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 2. Update app-runners.yaml

Edit `../app-runners.yaml` and add the custom image configuration:

```yaml
spec:
  source:
    helm:
      values: |
        template:
          spec:
            containers:
            - name: runner
              image: harbor.unifyops.io/library/arc-runner-unifyops:latest
              imagePullPolicy: Always
            imagePullSecrets:
            - name: harbor-registry-secret
```

### 3. Apply via GitOps

```bash
# Commit changes
git add .
git commit -m "Update ARC runners to use custom Harbor image"

# Push to trigger sync
git push origin main  # or dev/staging depending on your branch
```

### 4. Verify Deployment

```bash
# Check runner pods
kubectl get pods -n github-runners

# Check pod events
kubectl describe pod -n github-runners <pod-name>

# View runner logs
kubectl logs -n github-runners <pod-name> -f

# Verify tools are available
kubectl exec -n github-runners <pod-name> -- yq --version
kubectl exec -n github-runners <pod-name> -- kubectl version --client
kubectl exec -n github-runners <pod-name> -- helm version
```

## Updating Tool Versions

To update tool versions, edit the `Dockerfile` build arguments:

```dockerfile
ARG YQ_VERSION=v4.40.5
ARG KUBECTL_VERSION=v1.29.1
ARG HELM_VERSION=v3.14.0
```

**Important:** When updating versions, you must also update the SHA256 checksums:

```bash
# Get yq checksum
curl -sL "https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64" | sha256sum

# Get kubectl checksum
curl -sL "https://dl.k8s.io/release/v1.29.1/bin/linux/amd64/kubectl" | sha256sum

# Get helm checksum
curl -sL "https://get.helm.sh/helm-v3.14.0-linux-amd64.tar.gz" | sha256sum
```

Update the checksums in the Dockerfile:

```dockerfile
ARG YQ_SHA256=<new-checksum>
ARG KUBECTL_SHA256=<new-checksum>
ARG HELM_SHA256=<new-checksum>
```

## Maintenance

### Regular Updates
- **Weekly**: Check for security updates to base image
- **Monthly**: Update tool versions to latest stable releases
- **Quarterly**: Review and optimize image size

### Security Scanning

```bash
# Scan with Trivy (if installed)
trivy image harbor.unifyops.io/library/arc-runner-unifyops:latest

# Scan with Docker Scout
docker scout cves harbor.unifyops.io/library/arc-runner-unifyops:latest
```

### Image Size Optimization

```bash
# Check image size
docker images harbor.unifyops.io/library/arc-runner-unifyops

# Analyze layers
docker history harbor.unifyops.io/library/arc-runner-unifyops:latest
```

## Troubleshooting

### Runners not starting

```bash
# Check if image pull is failing
kubectl describe pod -n github-runners <pod-name> | grep -A 10 Events

# Verify Harbor secret
kubectl get secret harbor-registry-secret -n github-runners

# Test image pull manually
kubectl run test-pull --image=harbor.unifyops.io/library/arc-runner-unifyops:latest \
  --image-pull-policy=Always -n github-runners --rm -it -- /bin/bash
```

### Image pull authentication failures

```bash
# Verify Harbor credentials
docker login harbor.unifyops.io

# Recreate pull secret
kubectl delete secret harbor-registry-secret -n github-runners
kubectl create secret docker-registry harbor-registry-secret \
  --namespace=github-runners \
  --docker-server=harbor.unifyops.io \
  --docker-username=admin \
  --docker-password='YOUR_HARBOR_PASSWORD'
```

### Workflows still downloading tools

If workflows are still downloading `yq` or other tools:
1. Verify the runner is using the custom image: `kubectl describe pod -n github-runners <pod-name> | grep Image:`
2. Check that tools are in PATH: `kubectl exec -n github-runners <pod-name> -- which yq`
3. Update workflows to remove tool installation steps

## Performance Benefits

### Before (without custom image)
```yaml
- name: Install yq
  run: |
    curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /tmp/yq
    chmod +x /tmp/yq
  # ~5-10 seconds per workflow run
```

### After (with custom image)
```yaml
# No installation needed - tools are pre-installed
# ~0 seconds - immediate availability
```

**Estimated time savings:** 10-30 seconds per workflow run
**With 100 workflow runs/day:** 16-50 minutes saved daily

## References

- [GitHub Actions Runner Controller](https://github.com/actions/actions-runner-controller)
- [GitHub Actions Runner Images](https://github.com/actions/runner)
- [Harbor Documentation](https://goharbor.io/docs/)
- [Docker BuildKit](https://docs.docker.com/build/buildkit/)
