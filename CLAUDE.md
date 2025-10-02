# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is the UnifyOps infrastructure repository for Kubernetes GitOps deployments using ArgoCD. It manages a k3s home cluster with branch-based environments (dev/staging/prod) and comprehensive infrastructure services including Harbor registry, cert-manager, Longhorn storage, observability stack, and application deployments.

## Key Commands

### Cluster Bootstrap

Initial cluster setup (one-time operation):

```bash
# Bootstrap ArgoCD
cd bootstrap
./bootstrap.sh

# Apply root app-of-apps
kubectl apply -f clusters/unifyops-home/apps/root-apps.yaml

# Verify ArgoCD installation
kubectl get pods -n argocd
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

### GitOps Deployment Workflow

```bash
# Development deployment
git checkout dev
# Make changes
git commit -am "Your changes"
git push origin dev  # Auto-syncs to uo-dev namespace

# Staging promotion
git checkout staging
git merge dev
git push origin staging  # Auto-syncs to uo-staging namespace

# Production deployment
git checkout main
git merge staging
git push origin main
argocd app sync unifyops-prod  # Manual sync required

# Check application status
kubectl get applications -n argocd
argocd app list
argocd app get <app-name>
```

### Secret Management

```bash
# Create database secrets for all environments
./scripts/create-db-secrets.sh

# Create JWT secrets for all environments
./scripts/create-jwt-secrets.sh

# Verify secrets exist
kubectl get secrets -n uo-dev
kubectl get secrets -n uo-staging
kubectl get secrets -n uo-prod

# Rotate a secret
kubectl create secret generic auth-postgresql-secret \
  --namespace=uo-dev \
  --from-literal=postgres-password='<new-password>' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/auth-service -n uo-dev
```

### Harbor Registry Operations

```bash
# Login to Harbor
docker login harbor.unifyops.io

# Tag and push images
docker tag myapp:latest harbor.unifyops.io/library/myapp:latest
docker push harbor.unifyops.io/library/myapp:latest

# Mirror Bitnami images (for airgap deployments)
./scripts/mirror-bitnami-images.sh
./scripts/mirror-postgresql-amd64.sh
```

### Monitoring and Troubleshooting

```bash
# View application logs
kubectl logs -n uo-dev deployment/auth-service
kubectl logs -n uo-dev deployment/auth-api -f

# Check ArgoCD sync status
argocd app sync-status auth-service-dev

# Force sync an application
argocd app sync auth-service-dev --prune

# View ArgoCD events
kubectl get events -n argocd --sort-by='.lastTimestamp'

# Check Longhorn storage
kubectl get nodes.longhorn.io -n longhorn-system
kubectl get volumes -n longhorn-system

# Access UIs (requires DNS/hosts configuration)
# ArgoCD: https://argocd.unifyops.io
# Harbor: https://harbor.unifyops.io
# Grafana: https://grafana.unifyops.io
# Longhorn: https://longhorn.unifyops.io
```

## Architecture

### Repository Structure

```
unifyops-infra/
├── bootstrap/                    # Initial cluster setup
│   ├── bootstrap.sh              # ArgoCD installation script
│   └── README.md                 # Bootstrap instructions
│
├── clusters/                     # Cluster configurations
│   └── unifyops-home/
│       ├── apps/                 # ArgoCD Application definitions
│       │   ├── root-apps.yaml    # App-of-apps pattern root
│       │   ├── appset-unifyops.yaml  # ApplicationSet for multi-env deployment
│       │   ├── argocd/           # ArgoCD UI/ingress config
│       │   ├── auth/             # Auth stack applications
│       │   ├── cert-manager/     # TLS certificate management
│       │   ├── external-dns/     # Automatic DNS management
│       │   ├── github-runner/    # Self-hosted GitHub Actions runners
│       │   ├── harbor/           # Container & Helm registry
│       │   ├── longhorn/         # Distributed block storage
│       │   ├── metallb/          # Load balancer for bare metal
│       │   ├── metrics-server/   # Resource metrics
│       │   ├── nginx-private/    # Private ingress controller
│       │   ├── observability/    # Prometheus, Grafana, Loki, Tempo
│       │   ├── sealed-secret/    # Encrypted secrets in Git
│       │   ├── tailscale/        # VPN mesh networking
│       │   ├── trilium/          # Note-taking app
│       │   └── unifyops/         # UnifyOps application deployments
│       ├── namespaces/           # Namespace definitions with policies
│       │   ├── uo-dev/           # Dev namespace + network policies
│       │   ├── uo-staging/       # Staging namespace + network policies
│       │   ├── uo-prod/          # Prod namespace + network policies
│       │   └── uo-infra/         # Infrastructure namespace
│       └── projects/             # ArgoCD project RBAC
│           ├── apps-project.yaml # Application project
│           ├── infra-project.yaml # Infrastructure project
│           └── homelab-project.yaml # Homelab apps
│
├── apps/                         # Reusable application bases (Kustomize)
│   ├── argocd/
│   ├── cert-manager/
│   └── longhorn/
│
├── argocd/                       # Repository secrets
│   ├── harbor-helm-repo-sealed.yaml
│   └── repo-secrets.yaml
│
├── scripts/                      # Utility scripts
│   ├── create-db-secrets.sh      # PostgreSQL secret creation
│   ├── create-jwt-secrets.sh     # JWT secret creation
│   └── mirror-*.sh               # Image mirroring for airgap
│
└── docs/                         # Documentation
    ├── GITOPS-WORKFLOW.md        # Complete GitOps workflow
    ├── INGRESS-ROUTING.md        # Ingress routing patterns
    └── SECRET-MANAGEMENT.md      # Secret handling guide
```

### Infrastructure Components

The cluster runs the following infrastructure services:

1. **ArgoCD**: GitOps continuous deployment with app-of-apps pattern
   - Root application: `clusters/unifyops-home/apps/root-apps.yaml`
   - Manages all cluster applications declaratively
   - Branch-based environment deployment

2. **Harbor**: Container and Helm chart registry
   - URL: https://harbor.unifyops.io
   - Includes ChartMuseum for Helm charts
   - Longhorn-backed persistent storage

3. **Cert-Manager**: Automated TLS certificate management
   - Let's Encrypt integration for production certs
   - Route53 DNS-01 challenge solver
   - Automated certificate renewal

4. **External-DNS**: Automatic DNS record management
   - Route53 integration
   - Syncs ingress hostnames to DNS automatically

5. **Longhorn**: Distributed block storage system
   - NVMe-backed storage at `/var/lib/longhorn`
   - 3.6TB capacity
   - Web UI: https://longhorn.unifyops.io

6. **MetalLB**: Load balancer for bare metal
   - L2 advertisement mode
   - IP address pool for LoadBalancer services

7. **NGINX Ingress Controller (Private)**
   - Internal ingress for private services
   - TLS termination
   - Path-based routing

8. **Observability Stack**
   - **Prometheus**: Metrics collection and alerting
   - **Grafana**: Visualization and dashboards (https://grafana.unifyops.io)
   - **Loki**: Log aggregation
   - **Tempo**: Distributed tracing
   - **Alloy**: Observability data collection agent

9. **Sealed Secrets**: Encrypted secrets in Git
   - Allows GitOps for secret management
   - Secrets encrypted with cluster-specific key

10. **Metrics Server**: Resource metrics for HPA and kubectl top

11. **Tailscale**: VPN mesh networking for secure cluster access

12. **GitHub Actions Runners**: Self-hosted runners in cluster

### Key Design Decisions

1. **GitOps Pattern**: All cluster state managed via Git
   - ArgoCD continuously syncs cluster state with Git repository
   - Root app-of-apps pattern in `clusters/unifyops-home/apps/root-apps.yaml`
   - No manual kubectl applies for managed resources

2. **Branch-Based Environments**: Git branches map to environments
   - `dev` branch → `uo-dev` namespace (auto-sync enabled)
   - `staging` branch → `uo-staging` namespace (auto-sync enabled)
   - `main` branch → `uo-prod` namespace (manual sync required)

3. **ApplicationSet Pattern**: Multi-environment deployments
   - Single ApplicationSet generates apps for all environments
   - Environment-specific values in overlays
   - Reduces configuration duplication

4. **Namespace Isolation**: Each environment has dedicated namespace
   - Network policies enforce isolation
   - Resource quotas and limit ranges
   - Separate secrets per environment

5. **Storage Architecture**: Longhorn for persistent volumes
   - Dedicated 3.6TB NVMe storage at `/var/lib/longhorn`
   - Replicated volumes for high availability
   - Snapshot and backup capabilities

6. **Security Practices**
   - Sealed Secrets for GitOps-friendly secret management
   - Network policies restrict inter-pod communication
   - TLS everywhere via cert-manager
   - Harbor for trusted container images

7. **Ingress Strategy**: Path-based and subdomain routing
   - APIs: `/{app-type}/{stack-name}` (e.g., `/api/auth`)
   - Frontend apps: `{stack}.{env}.unifyops.io`
   - See INGRESS-ROUTING.md for details

## ArgoCD Project Structure

Projects define RBAC and resource boundaries:

### `apps` Project
- **Purpose**: UnifyOps application deployments
- **Namespaces**: `uo-dev`, `uo-staging`, `uo-prod`
- **Source Repos**:
  - https://github.com/KominskyOrg/unifyops-infra.git
  - oci://harbor.unifyops.io/library/unifyops-stack
- **Auto-sync**: Enabled for dev/staging, manual for prod

### `infra` Project
- **Purpose**: Infrastructure components
- **Namespaces**: All namespaces (including cert-manager, longhorn-system, etc.)
- **Source Repos**: Multiple Helm repositories (see clusters/unifyops-home/projects/infra-project.yaml:9)
- **Auto-sync**: Enabled for all components

### `homelab` Project
- **Purpose**: Personal/homelab applications (trilium, etc.)
- **Namespaces**: Homelab-specific namespaces
- **Auto-sync**: Enabled

## Common Workflows

### Adding a New Application

1. **Create Application definition** in appropriate directory:
   ```bash
   # For infrastructure component
   clusters/unifyops-home/apps/myapp/app.yaml

   # For UnifyOps stack application
   clusters/unifyops-home/apps/auth/  # Example structure
   ```

2. **Define ArgoCD Application**:
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: myapp
     namespace: argocd
   spec:
     project: infra  # or 'apps' for UnifyOps applications
     source:
       repoURL: https://charts.example.com
       chart: myapp
       targetRevision: "1.0.0"
     destination:
       server: https://kubernetes.default.svc
       namespace: myapp-namespace
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
   ```

3. **Apply via root app** (automatically synced):
   ```bash
   git add clusters/unifyops-home/apps/myapp/
   git commit -m "Add myapp application"
   git push origin main
   # ArgoCD will detect and deploy automatically
   ```

### Deploying UnifyOps Applications

UnifyOps applications use the ApplicationSet pattern:

1. **Update application code** in `unifyops` repository
2. **Build and push images** to Harbor:
   ```bash
   # Images should be tagged as: harbor.unifyops.io/library/{app-name}:{tag}
   docker build -t harbor.unifyops.io/library/auth-service:dev-latest .
   docker push harbor.unifyops.io/library/auth-service:dev-latest
   ```

3. **Deploy to environment** via branch push:
   ```bash
   # For dev
   git checkout dev
   git push origin dev  # Auto-deploys to uo-dev

   # For staging
   git checkout staging
   git merge dev
   git push origin staging  # Auto-deploys to uo-staging

   # For production
   git checkout main
   git merge staging
   git push origin main
   argocd app sync unifyops-prod  # Manual sync
   ```

### Managing Secrets

**CRITICAL**: Never commit secrets to Git. Use the provided scripts:

```bash
# Initial setup - creates secrets in all namespaces
./scripts/create-db-secrets.sh    # PostgreSQL passwords
./scripts/create-jwt-secrets.sh   # JWT signing keys

# Verify secrets
kubectl get secrets -n uo-dev | grep -E "(postgresql|jwt)"

# For new secrets, use Sealed Secrets:
kubectl create secret generic my-secret \
  --from-literal=key=value \
  --dry-run=client -o yaml > secret.yaml

kubeseal --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  < secret.yaml > sealed-secret.yaml

rm secret.yaml  # IMPORTANT: Delete plaintext
kubectl apply -f sealed-secret.yaml
```

See SECRET-MANAGEMENT.md for complete details.

### Troubleshooting Application Sync Issues

```bash
# Check application health
argocd app get myapp
kubectl get application myapp -n argocd -o yaml

# View sync errors
argocd app sync myapp --dry-run

# Force hard refresh
argocd app sync myapp --force --prune

# Check ArgoCD controller logs
kubectl logs -n argocd deployment/argocd-application-controller -f

# View resource events
kubectl get events -n target-namespace --sort-by='.lastTimestamp'
```

### Working with Helm Charts in Harbor

```bash
# Package a Helm chart
helm package ./my-chart

# Login to Harbor registry
helm registry login harbor.unifyops.io

# Push chart to Harbor
helm push my-chart-1.0.0.tgz oci://harbor.unifyops.io/library

# Use in ArgoCD Application
# source:
#   repoURL: oci://harbor.unifyops.io/library
#   chart: my-chart
#   targetRevision: "1.0.0"
```

## Critical Files and Configurations

### ArgoCD Core Files
- `clusters/unifyops-home/apps/root-apps.yaml`: Root app-of-apps application
  - Manages all applications in `clusters/unifyops-home/apps/`
  - Automatically syncs new applications
  - Located in `infra` project

- `clusters/unifyops-home/apps/appset-unifyops.yaml`: Multi-environment ApplicationSet
  - Generates applications for dev/staging/prod
  - Maps branches to namespaces
  - Uses overlay pattern for environment-specific config

### Project Definitions
- `clusters/unifyops-home/projects/apps-project.yaml`: Application RBAC
- `clusters/unifyops-home/projects/infra-project.yaml`: Infrastructure RBAC
- `clusters/unifyops-home/projects/homelab-project.yaml`: Homelab apps RBAC

### Namespace Policies
- `clusters/unifyops-home/namespaces/uo-{dev,staging,prod}/`
  - `namespace.yaml`: Namespace definition
  - `networkpolicies.yaml`: Pod-to-pod communication rules
  - `limitranges.yaml`: Default resource limits
  - `resourcequotas.yaml`: Namespace resource caps

### Infrastructure Applications
- `clusters/unifyops-home/apps/harbor/app.yaml`: Container registry config
- `clusters/unifyops-home/apps/cert-manager/`: TLS certificate management
- `clusters/unifyops-home/apps/longhorn/`: Persistent storage
- `clusters/unifyops-home/apps/observability/`: Prometheus/Grafana stack

### Sealed Secrets
- `clusters/unifyops-home/apps/*/secrets/*.sealed.yaml`: Encrypted secrets
- `argocd/harbor-helm-repo-sealed.yaml`: Harbor Helm repository credentials
- Requires cluster-specific sealing key (never commit unsealed secrets)

### Documentation
- `GITOPS-WORKFLOW.md`: Complete GitOps deployment workflow
- `INGRESS-ROUTING.md`: URL routing patterns and ingress strategy
- `SECRET-MANAGEMENT.md`: Secret handling and rotation procedures
- `bootstrap/README.md`: Initial cluster setup instructions

### Cluster Information
- **Node**: um790 (single-node k3s cluster)
- **SSH Access**: `ssh unifyops`
- **Storage**: 3.6TB NVMe at `/var/lib/longhorn`
- **Domain**: unifyops.io (Route53 managed)
- **Load Balancer**: MetalLB with L2 advertisement