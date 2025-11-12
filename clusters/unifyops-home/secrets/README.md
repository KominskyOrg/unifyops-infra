# Sealed Secrets Management

This directory contains encrypted Kubernetes secrets using [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets).

## Directory Structure

```
secrets/
├── dev/           # Development environment sealed secrets (encrypted, safe to commit)
├── staging/       # Staging environment sealed secrets (encrypted, safe to commit)
└── prod/          # Production environment secrets (NOT committed to Git)
```

## How Sealed Secrets Work

1. **Regular Secret**: Plain Kubernetes secret (sensitive data)
2. **Sealed Secret**: Encrypted version that can be safely committed to Git
3. **Controller**: Decrypts SealedSecrets and creates regular Secrets in the cluster

Only the cluster's Sealed Secrets controller can decrypt the sealed secrets.

## Prerequisites

- `kubeseal` CLI installed: `brew install kubeseal`
- Access to the Kubernetes cluster
- Sealed Secrets controller running in the cluster

## Creating Sealed Secrets

### Step 1: Create a Regular Kubernetes Secret

```bash
# Example: JWT secret for auth service
kubectl create secret generic auth-jwt-secret \
  --from-literal=jwt-secret='your-secure-random-jwt-key-here' \
  --dry-run=client \
  -o yaml > auth-jwt-secret.yaml
```

### Step 2: Seal the Secret

```bash
# Seal for a specific namespace and environment
kubeseal --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml \
  --namespace=uo-dev \
  < auth-jwt-secret.yaml \
  > dev/auth-jwt-sealed.yaml

# Clean up the plain secret file
rm auth-jwt-secret.yaml
```

### Step 3: Commit the Sealed Secret

```bash
git add dev/auth-jwt-sealed.yaml
git commit -m "Add sealed JWT secret for dev environment"
git push
```

### Step 4: Apply via ArgoCD or kubectl

The sealed secret will be automatically synced by ArgoCD, or you can manually apply:

```bash
kubectl apply -f dev/auth-jwt-sealed.yaml
```

The controller will decrypt it and create a regular secret `auth-jwt-secret` in the `uo-dev` namespace.

## Generating Strong Secrets

### Random String (JWT keys, API keys)
```bash
openssl rand -base64 32
```

### Random Hex (Database passwords)
```bash
openssl rand -hex 32
```

### UUID (API keys, service keys)
```bash
uuidgen | tr '[:upper:]' '[:lower:]'
```

## Current Secrets by Environment

### Development (uo-dev namespace)
- `auth-jwt-secret` - JWT signing key for auth service and API
- `auth-postgresql-secret` - PostgreSQL database passwords (managed by Helm subchart)

### Staging (uo-staging namespace)
- `auth-jwt-secret` - JWT signing key for auth service and API
- `auth-postgresql-secret` - PostgreSQL database passwords (managed by Helm subchart)

### Production (uo-prod namespace)
⚠️ **Production secrets are NOT stored in Git**

Production secrets should be:
1. Created directly in the cluster using `kubectl create secret`
2. Or created as sealed secrets locally and applied without committing
3. Backed up securely outside of Git (password manager, vault, etc.)

## Updating Secrets

### For Dev/Staging
1. Create new sealed secret with updated values
2. Apply to cluster (will update existing secret)
3. Commit new sealed secret file
4. Restart affected pods: `kubectl rollout restart deployment/<name> -n <namespace>`

### For Production
1. Create secret directly with `kubectl create secret --dry-run=client -o yaml | kubectl apply -f -`
2. Or update existing: `kubectl edit secret <name> -n uo-prod`
3. Restart affected pods

## Secret Rotation Policy

- **JWT Keys**: Rotate every 90 days or on suspected compromise
- **Database Passwords**: Rotate every 180 days or on suspected compromise
- **API Keys**: Rotate when team members leave or on suspected compromise

## Troubleshooting

### Check if sealed secret was decrypted
```bash
kubectl get secret auth-jwt-secret -n uo-dev
```

### View sealed secret controller logs
```bash
kubectl logs -n sealed-secrets deployment/sealed-secrets
```

### Verify secret contents (base64 decoded)
```bash
kubectl get secret auth-jwt-secret -n uo-dev -o jsonpath='{.data.jwt-secret}' | base64 -d
```

### Re-seal a secret (e.g., after cluster key rotation)
```bash
# Fetch public cert
kubeseal --fetch-cert \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  > pub-cert.pem

# Create sealed secret using the cert
kubeseal --cert=pub-cert.pem \
  --format=yaml \
  --namespace=uo-dev \
  < secret.yaml \
  > sealed-secret.yaml
```

## Security Best Practices

1. ✅ **Do commit**: Sealed secrets for dev/staging
2. ❌ **Never commit**: Plain secrets, production secrets, `.pem` files
3. ✅ **Use strong secrets**: Minimum 32 bytes of randomness
4. ✅ **Rotate regularly**: Follow rotation policy above
5. ✅ **Namespace-specific**: Seal secrets for specific namespaces
6. ✅ **Backup production**: Store prod secrets in secure vault/password manager

## Integration with ArgoCD

Sealed secrets in this directory can be referenced in ArgoCD Applications:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: auth-secrets
spec:
  source:
    path: clusters/unifyops-home/secrets/dev
    # ArgoCD will sync and apply sealed secrets
```

Or include them in the main app manifests directory for automatic sync.

## Migration from Existing Secrets

If you have existing secrets in the cluster that need to be converted to sealed secrets:

```bash
# Export existing secret
kubectl get secret auth-jwt-secret -n uo-dev -o yaml > temp-secret.yaml

# Remove cluster-specific fields
# Edit temp-secret.yaml and remove: resourceVersion, uid, creationTimestamp, etc.

# Seal it
kubeseal --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml \
  < temp-secret.yaml \
  > dev/auth-jwt-sealed.yaml

# Clean up
rm temp-secret.yaml

# Commit sealed version
git add dev/auth-jwt-sealed.yaml
git commit -m "Convert auth-jwt-secret to sealed secret"
```

## Future: AWS Secrets Manager Integration

This sealed secrets approach is designed for easy migration to AWS Secrets Manager:

1. Keep same secret names and keys
2. Change from SealedSecret to ExternalSecret (via External Secrets Operator)
3. Update references from local sealed secrets to AWS ARNs

Example future migration:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: auth-jwt-secret
spec:
  secretStoreRef:
    name: aws-secrets-manager
  target:
    name: auth-jwt-secret
  data:
    - secretKey: jwt-secret
      remoteRef:
        key: unifyops/prod/auth-jwt
```
