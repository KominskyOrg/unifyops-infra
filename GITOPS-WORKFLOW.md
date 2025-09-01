# UnifyOps GitOps Workflow

This document describes the GitOps workflow for deploying UnifyOps applications using ArgoCD, Harbor, and Helm.

## Overview

The UnifyOps GitOps workflow implements a fully automated deployment pipeline that:
- Builds and stores Docker images in Harbor
- Manages Helm charts for standardized deployments
- Uses ArgoCD ApplicationSets for multi-environment deployments
- Implements branch-based environment promotion (dev → staging → prod)

## Architecture Components

### 1. Repositories

- **unifyops**: Monorepo containing all application source code
- **unifyops-helm**: Unified Helm chart for all UnifyOps stacks
- **unifyops-infra**: GitOps configuration and environment-specific values

### 2. Infrastructure

- **Harbor**: Container registry and Helm chart repository
- **ArgoCD**: GitOps continuous deployment
- **Kubernetes**: Target deployment platform

## Workflow Process

### Development Cycle

1. **Code Development**
   ```
   git checkout -b feature/new-feature
   # Make changes to unifyops repo
   git commit -m "Add new feature"
   git push origin feature/new-feature
   # Create PR to dev branch
   ```

2. **Automatic Deployment to Dev**
   - PR merged to `dev` branch
   - GitHub Actions builds Docker images
   - Images pushed to Harbor with `dev-latest` tag
   - ArgoCD auto-syncs to dev environment

3. **Promotion to Staging**
   ```
   git checkout staging
   git merge dev
   git push origin staging
   ```
   - Images rebuilt with `staging-latest` tag
   - ArgoCD auto-syncs to staging environment

4. **Production Deployment**
   ```
   git checkout main
   git merge staging
   git push origin main
   ```
   - Images rebuilt with `prod-latest` tag
   - ArgoCD requires manual sync for production

## Directory Structure

### unifyops-infra Repository

```
apps/
└── unifyops/
    └── identity/
        └── auth/
            ├── auth-service/
            │   ├── values-dev.yaml
            │   ├── values-staging.yaml
            │   └── values-prod.yaml
            ├── auth-api/
            │   ├── values-dev.yaml
            │   ├── values-staging.yaml
            │   └── values-prod.yaml
            └── auth-app/
                ├── values-dev.yaml
                ├── values-staging.yaml
                └── values-prod.yaml

clusters/
└── unifyops-home/
    └── apps/
        ├── appset-auth.yaml      # ApplicationSet for auth stack
        ├── appset-user.yaml      # ApplicationSet for user stack
        └── appset-unifyops.yaml  # Legacy ApplicationSet
```

## ArgoCD ApplicationSet Configuration

The ApplicationSet automatically generates applications for each combination of:
- Environment (dev, staging, prod)
- App type (service, api, app)
- Stack (auth, user, etc.)

Example ApplicationSet creates:
- auth-service-dev
- auth-api-dev
- auth-app-dev
- auth-service-staging
- auth-api-staging
- auth-app-staging
- auth-service-prod
- auth-api-prod
- auth-app-prod

## CI/CD Pipelines

### Chart Publishing (unifyops-helm)

Triggered on changes to Chart.yaml or templates/:
1. Package Helm chart
2. Push to Harbor chart repository (when configured)
3. Create GitHub release as backup

### Image Building (unifyops)

Triggered on push to dev/staging/main branches:
1. Detect changed applications
2. Build Docker images for changed apps
3. Push to Harbor with environment-specific tags
4. Update image tags in values files (future enhancement)

## Harbor Configuration

### Registry Structure

```
harbor.unifyops.io/
├── library/           # Main project
│   ├── auth-service   # Docker images
│   ├── auth-api
│   ├── auth-app
│   └── ...
└── charts/           # Helm charts
    └── unifyops-stack
```

### Authentication

- Harbor credentials stored as sealed secrets
- ArgoCD configured with Harbor repository access
- GitHub Actions use Harbor secrets for pushing

## Adding a New Application

1. **Create the application** in unifyops repo:
   ```
   identity/newapp/
   ├── newapp-service/
   ├── newapp-api/
   └── newapp-app/
   ```

2. **Add values files** in unifyops-infra:
   ```
   apps/unifyops/identity/newapp/
   ├── newapp-service/values-{dev,staging,prod}.yaml
   ├── newapp-api/values-{dev,staging,prod}.yaml
   └── newapp-app/values-{dev,staging,prod}.yaml
   ```

3. **Create ApplicationSet**:
   ```yaml
   # clusters/unifyops-home/apps/appset-newapp.yaml
   apiVersion: argoproj.io/v1alpha1
   kind: ApplicationSet
   metadata:
     name: newapp-stack
     namespace: argocd
   spec:
     # ... (similar to auth stack)
   ```

4. **Deploy**:
   ```bash
   # Apply the ApplicationSet
   kubectl apply -f clusters/unifyops-home/apps/appset-newapp.yaml
   
   # Push code to trigger deployment
   git push origin dev
   ```

## Environment-Specific Configuration

### Development
- Namespace: `uo-dev`
- Branch: `dev`
- Auto-sync: Enabled
- Resources: Minimal
- Replicas: 1

### Staging
- Namespace: `uo-staging`
- Branch: `staging`
- Auto-sync: Enabled
- Resources: Moderate
- Replicas: 2

### Production
- Namespace: `uo-prod`
- Branch: `main`
- Auto-sync: Disabled (manual approval required)
- Resources: Full
- Replicas: 3+

## Secrets Management

All sensitive data is managed using:
- **Sealed Secrets**: For Git-stored encrypted secrets
- **Harbor credentials**: Stored as sealed secrets
- **Application secrets**: Environment-specific, stored as sealed secrets

Example creating a sealed secret:
```bash
# Create raw secret
kubectl create secret generic app-secret \
  --from-literal=key=value \
  --dry-run=client -o yaml > secret-raw.yaml

# Seal it
kubeseal --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  < secret-raw.yaml > secret-sealed.yaml

# Apply sealed secret
kubectl apply -f secret-sealed.yaml

# Delete raw secret
rm secret-raw.yaml
```

## Monitoring and Troubleshooting

### Check Application Status
```bash
# List all applications
argocd app list

# Get specific app details
argocd app get auth-service-dev

# Check sync status
argocd app sync-status auth-service-dev
```

### View Logs
```bash
# Application logs
kubectl logs -n uo-dev deployment/auth-service

# ArgoCD controller logs
kubectl logs -n argocd deployment/argocd-application-controller
```

### Manual Sync
```bash
# Sync specific application
argocd app sync auth-service-dev

# Sync with prune
argocd app sync auth-service-dev --prune
```

### Rollback
```bash
# View history
argocd app history auth-service-dev

# Rollback to previous version
argocd app rollback auth-service-dev <revision>
```

## Best Practices

1. **Never commit secrets** - Use sealed secrets
2. **Test in dev first** - All changes go through dev → staging → prod
3. **Use semantic versioning** - Tag releases properly
4. **Monitor resource usage** - Adjust limits based on metrics
5. **Document changes** - Update values files with comments
6. **Review before production** - Manual sync for production deployments

## Future Enhancements

- [ ] Automated image tag updates in values files
- [ ] Prometheus metrics integration
- [ ] Automated rollback on failures
- [ ] Blue-green deployments for production
- [ ] Integration tests in staging
- [ ] Cost optimization through resource analysis

## Support

For issues or questions:
- Check ArgoCD UI: https://argocd.unifyops.io
- Check Harbor UI: https://harbor.unifyops.io
- Review logs in Grafana: https://grafana.unifyops.io