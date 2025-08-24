# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is the UnifyOps infrastructure repository containing Terraform configurations for AWS infrastructure and GitOps configurations for Kubernetes deployments. It follows a modular approach with separate environments and service-oriented architecture.

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

- **envs/**: GitOps environment configurations using Kustomize
  - Separate directories for dev, staging, prod, and infra environments
  - Each environment has overlays for environment-specific customizations

- **apps/**: Kubernetes application manifests
  - ArgoCD for GitOps continuous deployment
  - Demo applications and supporting services

- **clusters/**: Cluster-specific configurations
  - Bootstrap configurations for cluster initialization

### Infrastructure Components

1. **VPC and Networking**: Module-based VPC with public/private subnets across multiple AZs
2. **ECS Cluster**: Supports both EC2 and Fargate launch types for containerized workloads
3. **RDS Database**: PostgreSQL instances with environment-specific configurations
4. **Security Groups**: Layered security with least-privilege access patterns

### Key Design Decisions

- **Cost Optimization**: Defaults to AWS Free Tier eligible resources (t2.micro EC2 instances)
- **Modularity**: Terraform modules for reusable infrastructure components
- **GitOps**: Kustomize-based deployments for Kubernetes applications
- **Multi-Repository Pattern**: Infrastructure (this repo) separated from application code (unifyops-core)

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

## Critical Files

- `tf/secrets.tfvars`: Contains sensitive variables (not in version control)
- `tf/plan.tfplan`: Terraform plan output file (generated, not committed)
- `Makefile`: Primary interface for all Terraform operations