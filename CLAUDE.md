# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is the UnifyOps infrastructure repository containing both Terraform configurations for AWS infrastructure and Kubernetes GitOps configurations for on-premises deployments. The repository has evolved to support a hybrid approach with cloud infrastructure via Terraform and local Kubernetes cluster management via ArgoCD.

## Key Commands

### Terraform Infrastructure Management

All Terraform operations use the Makefile in the root directory. The common workflow is:

```bash
# Initialize Terraform with backend configuration
make init

# Format Terraform files
make fmt

# Validate Terraform configuration
make validate

# Plan changes (creates plan.tfplan file)
make plan

# Apply planned changes
make apply

# List current resources
make list

# Destroy infrastructure (use with caution)
make destroy
```

### Environment Variables

The Makefile supports environment-specific deployments through variables:

```bash
# Deploy to different environments
make plan INFRA_ENV=dev    # default
make plan INFRA_ENV=staging
make plan INFRA_ENV=prod

# Override AWS profile
make plan AWS_PROFILE=dev

# Pass additional Terraform variables
make plan ARGS="-var='ecr_repository_url=<ECR_REPO_URL>'"
```

## Architecture

### Repository Structure

The repository is organized into distinct functional areas:

- **tf/**: Terraform configurations for AWS infrastructure
  - Contains modular components (ECS, RDS, VPC via external modules)
  - Uses S3 backend for state management with DynamoDB locking
  - Supports multi-environment deployments (dev/staging/prod)

- **clusters/**: Cluster-specific GitOps configurations
  - `unifyops-home/bootstrap/`: Root app-of-apps pattern for ArgoCD
  - `unifyops-home/apps/`: ArgoCD Application definitions for each environment

- **envs/**: Environment-specific Kubernetes resources
  - Each environment (infra/dev/staging/prod) has its own namespace
  - Kustomize-based configuration with namespace isolation
  - Contains namespace definitions and environment-specific overlays

- **apps/**: Reusable Kubernetes application bases
  - `argocd/`: ArgoCD ingress and TLS configuration
  - `cert-manager/`: TLS certificate management
  - `longhorn/`: Persistent storage system configuration
  - `metrics-server/`: Cluster metrics collection
  - Applications use Kustomize for configuration management

- **projects/**: ArgoCD AppProject definitions for RBAC and resource isolation
  - Separate projects per environment with specific permissions
  - Controls which repositories and namespaces each project can access

- **argocd/**: ArgoCD repository configurations
  - Repository secrets for Git and Helm chart access

### Infrastructure Components

#### AWS Infrastructure (Terraform)
1. **VPC and Networking**: Module-based VPC with public/private subnets across multiple AZs
2. **ECS Cluster**: Supports both EC2 and Fargate launch types for containerized workloads
3. **RDS Database**: PostgreSQL instances with environment-specific configurations
4. **Security Groups**: Layered security with least-privilege access patterns

#### Kubernetes Infrastructure (GitOps)
1. **ArgoCD**: GitOps continuous deployment using app-of-apps pattern
2. **Cert-Manager**: Automated TLS certificate management with self-signed CA
3. **Longhorn**: Distributed block storage for persistent volumes
4. **Traefik**: Ingress controller for HTTP/HTTPS routing

### Key Design Decisions

- **GitOps Pattern**: ArgoCD manages all Kubernetes deployments from Git
- **App-of-Apps**: Root application in `clusters/unifyops-home/bootstrap/root-app.yaml` manages all other apps
- **Namespace Isolation**: Each environment runs in its own namespace with RBAC controls
- **Storage Architecture**: Dedicated NVMe storage for Kubernetes persistent volumes via Longhorn

## Working with Terraform Modules

When modifying or adding Terraform resources:

1. Modules are located in `tf/modules/`
2. Each module has its own variables.tf, outputs.tf, and resource files
3. The main configuration in `tf/main.tf` consumes these modules
4. Always run `make fmt` before committing Terraform changes
5. Use `make validate` to check syntax before planning

## Environment-Specific Configurations

The infrastructure supports three environments with isolated resources:

- **dev**: Development environment with minimal resources
- **staging**: Pre-production environment for testing
- **prod**: Production environment with enhanced redundancy

VPC CIDR blocks are pre-allocated per environment:
- dev: 10.0.0.0/16
- staging: 10.1.0.0/16  
- prod: 10.2.0.0/16

## Migration Context

The repository supports migration from EC2 to ECS containers. Two deployment options are available:
- ECS with EC2 launch type (Free Tier eligible)
- ECS with Fargate (pay-as-you-go, serverless)

See ECS_MIGRATION.md for detailed migration steps and cost comparisons.

## Kubernetes/GitOps Operations

### Deploying to Kubernetes

The cluster uses ArgoCD for GitOps deployments. To deploy changes:

```bash
# Push changes to trigger ArgoCD sync
git push origin main

# Or manually apply ArgoCD applications
kubectl apply -f clusters/unifyops-home/bootstrap/root-app.yaml

# Check application status
kubectl get applications -n argocd
```

### Managing ArgoCD Applications

```bash
# Access ArgoCD UI
# URL: http://argocd.local (requires /etc/hosts entry)

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# CLI operations (requires argocd CLI)
argocd app list
argocd app sync <app-name>
argocd app get <app-name>
```

### Storage Management

Longhorn provides persistent storage:

```bash
# Access Longhorn UI
# URL: http://longhorn.local (requires /etc/hosts entry)

# Fix storage issues
./scripts/fix-longhorn-storage.sh

# Check storage status
kubectl get nodes.longhorn.io -n longhorn-system
```

## Critical Files and Configurations

### Terraform Files
- `tf/secrets.tfvars`: Contains sensitive variables (not in version control)
- `tf/plan.tfplan`: Terraform plan output file (generated, not committed)
- `Makefile`: Primary interface for all Terraform operations

### Kubernetes/GitOps Files
- `clusters/unifyops-home/bootstrap/root-app.yaml`: Root ArgoCD application (app-of-apps)
- `apps/longhorn/values.yaml`: Longhorn storage configuration (update path for NVMe mount)
- `projects/*.yaml`: ArgoCD project definitions with RBAC settings

### Server Configuration
- **Cluster Location**: SSH accessible at `ssh unifyops`
- **Node Name**: um790
- **Storage**: 3.6TB NVMe mounted at `/var/lib/longhorn`
- **Ingress Domains**: *.local domains pointing to cluster IP