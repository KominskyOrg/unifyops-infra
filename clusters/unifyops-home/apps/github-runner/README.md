# GitHub Actions Self-Hosted Runner on Kubernetes

This setup allows GitHub Actions workflows to run directly on your Kubernetes cluster, giving them access to Harbor and other cluster resources.

## Quick Setup

### Option 1: Using Actions Runner Controller (Recommended)

1. **Create a GitHub Token**
   - Go to https://github.com/settings/tokens/new
   - Select scopes: `repo`, `admin:org` (for org-wide runners)
   - Save the token securely

2. **Run the setup script**
   ```bash
   chmod +x setup-runner.sh
   ./setup-runner.sh
   ```

3. **Or manually install**
   ```bash
   # Install ARC controller
   helm install arc \
     --namespace arc-systems \
     --create-namespace \
     oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller

   # Create secret with your GitHub token
   kubectl create namespace github-runners
   kubectl create secret generic github-token \
     --namespace=github-runners \
     --from-literal=github-token="YOUR_GITHUB_TOKEN"

   # Install runner scale set
   helm install unifyops-runner-set \
     --namespace github-runners \
     oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
     --set githubConfigUrl="https://github.com/KominskyOrg" \
     --set githubConfigSecret="github-token"
   ```

### Option 2: Simple Deployment (Basic)

1. **Get a runner registration token**
   - Go to your GitHub org settings → Actions → Runners
   - Click "New self-hosted runner"
   - Copy the token from the configuration instructions

2. **Create the secret**
   ```bash
   kubectl create namespace github-runner
   kubectl create secret generic github-runner-secret \
     --namespace=github-runner \
     --from-literal=runner-token="YOUR_RUNNER_TOKEN"
   ```

3. **Deploy the runner**
   ```bash
   kubectl apply -f namespace.yaml
   kubectl apply -f rbac.yaml
   kubectl apply -f deployment.yaml
   ```

## Using in GitHub Actions

Update your workflow to use the self-hosted runner:

```yaml
jobs:
  deploy:
    runs-on: self-hosted  # Instead of ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Access Harbor
        run: |
          # Harbor is accessible from within the cluster
          helm registry login harbor.unifyops.io
      
      - name: Deploy to Kubernetes
        run: |
          # kubectl is pre-configured with cluster access
          kubectl get pods -n default
```

## Features

- **Cluster Access**: Full kubectl access to your cluster
- **Harbor Access**: Can push/pull from private Harbor registry
- **Docker Support**: Docker-in-Docker for building images
- **Auto-scaling**: ARC automatically scales runners based on demand
- **Ephemeral**: Runners are created per job and destroyed after

## Monitoring

Check runner status:
```bash
# For ARC
kubectl get runners -n github-runners
kubectl get pods -n github-runners

# For simple deployment
kubectl get pods -n github-runner
kubectl logs -n github-runner -l app=github-runner
```

## Security Considerations

1. **Token Security**: Store GitHub tokens as Kubernetes secrets
2. **RBAC**: The runner has cluster-admin by default - restrict as needed
3. **Network Policies**: Consider adding network policies to limit runner access
4. **Resource Limits**: Set appropriate CPU/memory limits

## Customizing Runner Image

To add more tools to the runner, create a custom Dockerfile:

```dockerfile
FROM ghcr.io/actions/actions-runner:latest

USER root
RUN apt-get update && apt-get install -y \
    jq \
    yq \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

USER runner
```

Build and push to Harbor:
```bash
docker build -t harbor.unifyops.io/library/github-runner:custom .
docker push harbor.unifyops.io/library/github-runner:custom
```

Then update the deployment to use your custom image.

## Troubleshooting

### Runner not appearing in GitHub
- Check the token is valid: `kubectl describe secret github-token -n github-runners`
- Check runner logs: `kubectl logs -n github-runners -l app=github-runner`

### Harbor access issues
- Ensure runner pod can resolve Harbor DNS
- Check Harbor credentials in secrets

### Kubectl permission denied
- Review RBAC configuration
- Check ServiceAccount is properly attached to runner pod