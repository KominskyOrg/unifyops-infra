# Production Secrets

⚠️ **IMPORTANT**: Production secrets are NEVER committed to Git, even in encrypted form.

## Creating Production Secrets

### Option 1: Direct kubectl Creation (Recommended)

```bash
# Generate strong secret
JWT_SECRET=$(openssl rand -base64 32)
SERVICE_API_KEY=$(openssl rand -hex 32)

# Create JWT secret directly in cluster
kubectl create secret generic auth-jwt-secret \
  --from-literal=jwt-secret="$JWT_SECRET" \
  --namespace=uo-prod

# Create service API keys
kubectl create secret generic auth-service-api-keys \
  --from-literal=auth-service-key="$SERVICE_API_KEY" \
  --namespace=uo-prod

# Verify secrets were created
kubectl get secrets -n uo-prod | grep auth
```

### Option 2: Using create-prod-secrets.sh Script

```bash
# Run the helper script
./create-prod-secrets.sh

# Follow prompts to create each secret
```

### Option 3: Sealed Secrets (Without Committing)

If you want to use sealed secrets for production but NOT commit them:

```bash
# Create regular secret
kubectl create secret generic auth-jwt-secret \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --namespace=uo-prod \
  --dry-run=client -o yaml > temp-secret.yaml

# Seal it
kubeseal --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml \
  --namespace=uo-prod \
  < temp-secret.yaml \
  > auth-jwt-sealed.yaml

# Apply to cluster
kubectl apply -f auth-jwt-sealed.yaml

# Clean up (DO NOT COMMIT)
rm temp-secret.yaml auth-jwt-sealed.yaml
```

## Required Production Secrets

### 1. JWT Secret (`auth-jwt-secret`)
- **Purpose**: Signs and validates JWT tokens for authentication
- **Keys**: `jwt-secret`
- **Format**: Base64-encoded random string (32+ bytes)
- **Generation**: `openssl rand -base64 32`

### 2. Service API Keys (`auth-service-api-keys`)
- **Purpose**: Authenticates service-to-service API calls
- **Keys**: `auth-service-key`
- **Format**: Hex-encoded random string (32+ bytes)
- **Generation**: `openssl rand -hex 32`

### 3. Database Secrets (`auth-postgresql-secret`)
- **Purpose**: PostgreSQL database authentication
- **Keys**: `postgres-password`, `password`, `replication-password`
- **Note**: Managed by PostgreSQL Helm subchart
- **Generation**: `openssl rand -base64 24`

## Backup Strategy

⚠️ **CRITICAL**: Production secrets must be backed up securely!

### Option 1: Secure Password Manager
Store secrets in 1Password, LastPass, or similar:
- Namespace: `uo-prod`
- Secret name: `auth-jwt-secret`
- Key: `jwt-secret`
- Value: [paste the actual value]

### Option 2: Encrypted Backup File
```bash
# Export secret
kubectl get secret auth-jwt-secret -n uo-prod -o yaml > prod-backup.yaml

# Encrypt with GPG
gpg --symmetric --cipher-algo AES256 prod-backup.yaml

# Store prod-backup.yaml.gpg in secure location (not Git)
# Delete unencrypted file
rm prod-backup.yaml
```

### Option 3: AWS Secrets Manager (Future)
When migrating to AWS:
```bash
# Store in AWS Secrets Manager
aws secretsmanager create-secret \
  --name unifyops/prod/auth-jwt \
  --secret-string "$JWT_SECRET" \
  --region us-east-1
```

## Disaster Recovery

If secrets are lost:
1. **Check backup location**: Password manager, encrypted file, or AWS
2. **If unrecoverable**: Generate new secrets and update cluster
3. **Impact**: All users will be logged out (need to re-authenticate)
4. **Rollout**: Apply new secret and restart affected pods

```bash
# After creating new secret
kubectl rollout restart deployment/auth-service -n uo-prod
kubectl rollout restart deployment/auth-api -n uo-prod
```

## Rotation Schedule

- **JWT Keys**: Every 90 days or on compromise
- **Service API Keys**: Every 180 days or when team changes
- **Database Passwords**: Every 180 days or on compromise

## Security Checklist

- [ ] Secrets use strong randomness (openssl, not manual)
- [ ] Secrets are backed up in secure location
- [ ] Secrets are NOT committed to Git
- [ ] Access to production secrets is restricted
- [ ] Rotation schedule is documented
- [ ] Emergency procedures are documented
