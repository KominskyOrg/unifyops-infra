# Harbor Registry Deployment

Harbor is an enterprise-class container registry that provides image management, vulnerability scanning, and access control.

## Quick Start

### 1. Deploy Harbor via ArgoCD

```bash
# The Harbor application is already defined in clusters/unifyops-home/apps/harbor.yaml
# To deploy, commit and push to main branch
git add .
git commit -m "Add Harbor registry configuration"
git push origin main

# ArgoCD will automatically sync and deploy Harbor
```

### 2. Wait for Harbor to be Ready

```bash
# Check Harbor pods
kubectl get pods -n harbor

# Check Harbor application in ArgoCD
kubectl get application harbor -n argocd
```

### 3. Configure Harbor

```bash
# Run the bootstrap script to create projects and robot accounts
./apps/harbor/setup/bootstrap-harbor.sh

# This will:
# - Create dev, staging, prod projects
# - Generate robot accounts for CI/CD
# - Create Kubernetes pull secrets
```

### 4. Apply Image Pull Secrets

```bash
# Create namespaces if they don't exist
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace staging --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f -

# Apply the generated secrets
kubectl apply -f apps/harbor/setup/secrets/
```

## Configuration Details

### Harbor Access
- **URL**: https://harbor.local
- **Admin Username**: admin
- **Admin Password**: Harbor12345! (change in production)

### Projects Structure
- `dev` - Development images
- `staging` - Staging/QA images  
- `prod` - Production images

### Storage
Using Longhorn PVC storage:
- Registry: 200Gi
- Database: 20Gi
- Redis: 5Gi
- JobService: 20Gi
- ChartMuseum: 10Gi
- Trivy: 20Gi

## CI/CD Integration

### GitHub Actions
See `apps/harbor/examples/ci/github-actions-example.yaml` for a complete workflow.

Add robot tokens as GitHub secrets:
- `HARBOR_DEV_ROBOT_TOKEN`
- `HARBOR_STAGING_ROBOT_TOKEN`
- `HARBOR_PROD_ROBOT_TOKEN`

### Local Docker Usage

```bash
# Login to Harbor
docker login harbor.local

# Build and tag image
docker build -t harbor.local/dev/myapp:latest .

# Push to Harbor
docker push harbor.local/dev/myapp:latest
```

## Kubernetes Deployment

Update your deployments to use Harbor:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: dev
spec:
  template:
    spec:
      imagePullSecrets:
        - name: harbor-pull
      containers:
        - name: myapp
          image: harbor.local/dev/myapp:latest
```

## Migrating from Docker Registry

Since the old Docker Registry is empty, simply:

1. Deploy Harbor (done via ArgoCD)
2. Update all future deployments to use Harbor
3. Remove the old Docker Registry application

```bash
# Remove old Docker Registry via ArgoCD
kubectl delete application docker-registry -n argocd
```

## Security Features

### Enabled by Default
- **Vulnerability Scanning**: Automatic with Trivy
- **Image Signing**: Notary enabled for content trust
- **RBAC**: Project-based access control
- **Robot Accounts**: Service accounts for CI/CD

### Scan Policy
- Auto-scan on push: Enabled
- Severity threshold: HIGH, CRITICAL
- Ignore unfixed: Yes

## Maintenance

### Garbage Collection
Configured to run weekly on Saturday at 2 AM.

### Backup
PVCs are set to `retain` policy. Ensure regular backups of:
- `/data/registry` - Image blobs
- `/data/database` - PostgreSQL data

### Monitoring
Harbor exposes Prometheus metrics on `/metrics` endpoint.

## Troubleshooting

### Harbor Not Accessible
```bash
# Check pods
kubectl get pods -n harbor

# Check ingress
kubectl get ingress -n harbor

# Check logs
kubectl logs -n harbor deployment/harbor-core
```

### Image Push/Pull Issues
```bash
# Verify robot account
curl -u "robot\$dev_ci:TOKEN" https://harbor.local/api/v2.0/projects

# Check secret in namespace
kubectl get secret harbor-pull -n dev -o yaml
```

### Certificate Issues
If using self-signed certificates:
```bash
# For Docker
mkdir -p /etc/docker/certs.d/harbor.local
cp ca.crt /etc/docker/certs.d/harbor.local/

# For containerd/k8s nodes
# Add CA to system trust store
```

## References
- [Harbor Documentation](https://goharbor.io/docs/)
- [Harbor Helm Chart](https://github.com/goharbor/harbor-helm)