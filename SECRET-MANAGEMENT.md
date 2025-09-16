# Secret Management Guide

## Overview

This guide explains how to manage secrets securely in the UnifyOps infrastructure. All sensitive data (passwords, API keys, JWT secrets) must be stored in Kubernetes secrets and **NEVER** committed to Git.

## Security Principles

1. **No Secrets in Git**: Never commit passwords, API keys, or tokens to version control
2. **Use External Secrets**: All sensitive data should be stored as Kubernetes secrets
3. **Environment Isolation**: Each environment (dev, staging, prod) has its own secrets
4. **Secure Generation**: Use cryptographically secure methods to generate passwords
5. **Access Control**: Secrets are namespace-scoped and follow RBAC policies

## Required Secrets

### PostgreSQL Database Secrets

Each service that uses PostgreSQL requires a database secret with the following keys:
- `postgres-password`: Admin password for the postgres user
- `password`: Password for the application user
- `replication-password`: Password for database replication (if needed)

**Secret naming convention**: `{service-name}-postgresql-secret`

### JWT Authentication Secrets

Services that handle authentication require JWT secrets:
- `jwt-secret`: Secret key for signing JWT tokens

**Secret naming convention**: `{service-name}-jwt-secret`

## Creating Secrets

### Initial Setup

Run the provided scripts to create secrets for all environments:

```bash
# Create PostgreSQL secrets for all environments
./scripts/create-db-secrets.sh

# Create JWT secrets for all environments
./scripts/create-jwt-secrets.sh
```

**IMPORTANT**: Save the generated passwords in a secure password manager immediately!

### Manual Secret Creation

For individual secrets:

```bash
# PostgreSQL secret
kubectl create secret generic auth-postgresql-secret \
  --namespace=uo-dev \
  --from-literal=postgres-password='<secure-password>' \
  --from-literal=password='<secure-password>' \
  --from-literal=replication-password='<secure-password>'

# JWT secret
kubectl create secret generic auth-jwt-secret \
  --namespace=uo-dev \
  --from-literal=jwt-secret='<secure-jwt-key>'
```

### Using Custom Passwords

To use your own passwords instead of generated ones:

```bash
# Set environment variables before running the script
export DEV_POSTGRES_PASSWORD="your-custom-password"
export DEV_USER_PASSWORD="your-custom-password"
export DEV_JWT_SECRET="your-custom-jwt-secret"

# Then run the scripts
./scripts/create-db-secrets.sh
./scripts/create-jwt-secrets.sh
```

## Helm Chart Configuration

The Helm values files are configured to use external secrets:

```yaml
# PostgreSQL configuration
postgresql:
  auth:
    existingSecret: "auth-postgresql-secret"
    secretKeys:
      adminPasswordKey: "postgres-password"
      userPasswordKey: "password"
      replicationPasswordKey: "replication-password"

# JWT configuration
secrets:
  existingSecret: "auth-jwt-secret"
  existingSecretJwtKey: "jwt-secret"
```

## Verifying Secrets

### Check if secrets exist:

```bash
# List all secrets in a namespace
kubectl get secrets -n uo-dev
kubectl get secrets -n uo-staging
kubectl get secrets -n uo-prod

# View secret details (without showing values)
kubectl describe secret auth-postgresql-secret -n uo-dev
```

### Test secret values (be careful!):

```bash
# Decode a specific key (ONLY for debugging, avoid in production)
kubectl get secret auth-postgresql-secret -n uo-dev \
  -o jsonpath="{.data.postgres-password}" | base64 -d
```

## Rotating Secrets

To rotate secrets:

1. Generate new passwords
2. Update the Kubernetes secret
3. Restart the affected pods

```bash
# Update the secret
kubectl create secret generic auth-postgresql-secret \
  --namespace=uo-dev \
  --from-literal=postgres-password='<new-password>' \
  --from-literal=password='<new-password>' \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart the pods to pick up new secrets
kubectl rollout restart statefulset auth-service-postgresql -n uo-dev
kubectl rollout restart deployment auth-service -n uo-dev
```

## Backup and Recovery

### Backup Secrets

```bash
# Export secrets to encrypted files (use with caution)
kubectl get secret auth-postgresql-secret -n uo-prod -o yaml > auth-pg-secret-prod.yaml
# Encrypt the file immediately
gpg --encrypt --recipient your-email@example.com auth-pg-secret-prod.yaml
# Delete the unencrypted file
rm auth-pg-secret-prod.yaml
```

### Restore Secrets

```bash
# Decrypt and apply
gpg --decrypt auth-pg-secret-prod.yaml.gpg | kubectl apply -f -
```

## Security Checklist

- [ ] All passwords are generated using cryptographically secure methods
- [ ] No secrets are committed to Git
- [ ] Each environment has unique passwords
- [ ] Secrets are stored in a password manager
- [ ] Access to production secrets is restricted
- [ ] Regular secret rotation is scheduled
- [ ] Backup procedures are documented and tested

## Troubleshooting

### Pod cannot access secret

1. Verify the secret exists in the correct namespace
2. Check the secret name matches the Helm values
3. Ensure the pod has the correct service account permissions

### Database connection fails after secret update

1. The database password might be out of sync
2. Restart both the database and application pods
3. For PostgreSQL, you may need to update the password in the database itself

### ArgoCD sync issues

1. ArgoCD cannot create secrets automatically
2. Secrets must be created manually before deployment
3. Use the provided scripts for initial setup

## Future Improvements

Consider implementing:
- External Secrets Operator for cloud secret management
- Sealed Secrets for GitOps-friendly secret management
- HashiCorp Vault integration for enterprise secret management
- Automatic secret rotation policies