# GitOps Workflow Guide

## Branch Strategy

This repository follows a branch-based GitOps promotion workflow:

- **`dev` branch** → Deploys to development environment
- **`staging` branch** → Deploys to staging environment  
- **`main` branch** → Deploys to production environment

## Environment Promotion Flow

```
dev → staging → main
```

### Development Workflow

1. Create feature branch from `dev`:
   ```bash
   git checkout dev
   git pull origin dev
   git checkout -b feature/your-feature
   ```

2. Make changes and test locally

3. Push and create PR to `dev`:
   ```bash
   git push origin feature/your-feature
   # Create PR: feature/your-feature → dev
   ```

4. After merge, changes auto-deploy to dev environment

### Staging Promotion

1. When dev is stable, promote to staging:
   ```bash
   git checkout staging
   git pull origin staging
   git merge dev
   git push origin staging
   ```
   Or create PR: `dev → staging`

2. Changes auto-deploy to staging environment

### Production Deployment

1. After staging validation, promote to production:
   ```bash
   git checkout main
   git pull origin main
   git merge staging
   git push origin main
   ```
   Or create PR: `staging → main`

2. **Manual sync required** for production:
   ```bash
   argocd app sync env-prod
   ```
   Or sync via ArgoCD UI

## Hotfix Process

For critical production fixes:

1. Create hotfix from `main`:
   ```bash
   git checkout main
   git checkout -b hotfix/critical-fix
   ```

2. Apply fix and test

3. Merge to main and backport:
   ```bash
   # Merge to main first
   git checkout main
   git merge hotfix/critical-fix
   
   # Backport to staging and dev
   git checkout staging
   git cherry-pick <commit-hash>
   git checkout dev
   git cherry-pick <commit-hash>
   ```

## ArgoCD Configuration

### Auto-Sync Settings
- **Dev**: Auto-sync enabled (immediate deployment)
- **Staging**: Auto-sync enabled (immediate deployment)
- **Production**: Manual sync (requires approval)

### Branch Tracking
Each environment's ArgoCD application tracks its respective branch:

```yaml
# dev.yaml
targetRevision: dev

# staging.yaml  
targetRevision: staging

# prod.yaml
targetRevision: main
```

## Best Practices

1. **Never commit directly to main** - Always use PRs
2. **Test in dev first** - All changes start in dev
3. **Validate in staging** - Staging should mirror production
4. **Manual production sync** - Deliberate production deployments
5. **Tag production releases** - Create tags for production deployments:
   ```bash
   git tag -a v1.0.0 -m "Release v1.0.0"
   git push origin v1.0.0
   ```

## Rollback Procedures

### Quick Rollback
1. **Via ArgoCD UI**: Use "Rollback" button to previous sync
2. **Via CLI**: 
   ```bash
   argocd app rollback env-prod <revision>
   ```

### Git-based Rollback
1. Revert commits on the branch:
   ```bash
   git revert <commit-hash>
   git push origin main
   ```

2. For production, manually sync after revert

## Environment Isolation

Each environment is isolated through:
- Separate Kubernetes namespaces
- Dedicated ArgoCD projects with RBAC
- Branch-based deployment control
- Independent sync policies

This ensures changes in one environment don't affect others until explicitly promoted.