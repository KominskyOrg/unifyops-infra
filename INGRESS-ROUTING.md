# UnifyOps Ingress Routing Strategy

## Overview

UnifyOps uses a **path-based routing strategy** that leverages the existing endpoint pattern `/{app-type}/{stack-name}` for clean, predictable URL structures across all environments.

## URL Structure

### Development Environment
```
https://dev.unifyops.io/api/auth       → auth-api:8002
https://dev.unifyops.io/service/auth   → auth-service:8001  (testing only)
https://dev.unifyops.io/api/user       → user-api:8002
https://dev.unifyops.io/service/user   → user-service:8001  (testing only)

https://auth.dev.unifyops.io           → auth-app:3000
https://user.dev.unifyops.io           → user-app:3000
```

### Staging Environment
```
https://staging.unifyops.io/api/auth      → auth-api:8002
https://staging.unifyops.io/service/auth  → auth-service:8001  (optional)
https://staging.unifyops.io/api/user      → user-api:8002
https://staging.unifyops.io/service/user  → user-service:8001  (optional)

https://auth.staging.unifyops.io          → auth-app:3000
https://user.staging.unifyops.io          → user-app:3000
```

### Production Environment
```
https://api.unifyops.io/api/auth          → auth-api:8002
https://api.unifyops.io/api/user          → user-api:8002
# Services NOT exposed in production

https://auth.unifyops.io                  → auth-app:3000
https://user.unifyops.io                  → user-app:3000
```

## Routing Rules

### Path-Based Routing for APIs and Services

All API and service endpoints follow the pattern:
```
/{app-type}/{stack-name}/*
```

This means:
- `/api/auth/*` → Routes to auth-api
- `/service/auth/*` → Routes to auth-service (dev/staging only)
- `/api/user/*` → Routes to user-api
- `/service/user/*` → Routes to user-service (dev/staging only)

### Subdomain Routing for Frontend Apps

Frontend applications use subdomain routing:
- `{stack-name}.{env}.unifyops.io` for dev/staging
- `{stack-name}.unifyops.io` for production

## Ingress Configuration Examples

### API Gateway Ingress (Dev)
```yaml
ingress:
  enabled: true
  className: nginx-private
  hosts:
    - host: dev.unifyops.io
      paths:
        - path: /api/auth
          pathType: Prefix
  tls:
    - secretName: dev-unifyops-tls
      hosts:
        - dev.unifyops.io
```

### Backend Service Ingress (Dev Only)
```yaml
ingress:
  enabled: true  # Only in dev/staging
  className: nginx-private
  hosts:
    - host: dev.unifyops.io
      paths:
        - path: /service/auth
          pathType: Prefix
  tls:
    - secretName: dev-unifyops-tls
      hosts:
        - dev.unifyops.io
```

### Frontend App Ingress
```yaml
ingress:
  enabled: true
  className: nginx-private
  hosts:
    - host: auth.dev.unifyops.io
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: auth-dev-tls
      hosts:
        - auth.dev.unifyops.io
```

## Benefits of This Approach

### 1. **Simplified Certificate Management**
- Dev: Single wildcard cert for `*.dev.unifyops.io` and `dev.unifyops.io`
- Staging: Single wildcard cert for `*.staging.unifyops.io` and `staging.unifyops.io`
- Prod: Separate certs for `api.unifyops.io` and `*.unifyops.io`

### 2. **Clean URL Structure**
- APIs are clearly identified: `/api/{stack}`
- Services (when exposed) are clear: `/service/{stack}`
- Frontend apps get their own subdomains for better UX

### 3. **Security by Environment**
- **Dev**: Both APIs and services exposed for testing
- **Staging**: Services optionally exposed for integration testing
- **Production**: Only APIs exposed, services remain internal

### 4. **Consistent Endpoint Patterns**
Since your code already uses `/{app-type}/{stack-name}` patterns, the ingress routing aligns perfectly:
```python
# In your FastAPI apps
@router.get("/api/auth/login")
@router.get("/service/auth/health")
```

## Testing URLs

### Development Testing
```bash
# Test auth API
curl https://dev.unifyops.io/api/auth/health

# Test auth service directly (dev only)
curl https://dev.unifyops.io/service/auth/health

# Test auth frontend
curl https://auth.dev.unifyops.io
```

### API Communication Examples
```javascript
// Frontend to API
const apiUrl = "https://dev.unifyops.io/api/auth/login";

// API to API (internal)
const userApiUrl = "http://user-api:8002/api/user/profile";

// API to Service (internal)
const authServiceUrl = "http://auth-service:8001/service/auth/validate";
```

## DNS Requirements

### Development
```
dev.unifyops.io           → Ingress Controller IP
*.dev.unifyops.io         → Ingress Controller IP
```

### Staging
```
staging.unifyops.io       → Ingress Controller IP
*.staging.unifyops.io     → Ingress Controller IP
```

### Production
```
api.unifyops.io           → Ingress Controller IP
*.unifyops.io             → Ingress Controller IP
```

## Adding a New Stack

When adding a new stack (e.g., `billing`):

1. **API Gateway** will automatically be available at:
   - Dev: `https://dev.unifyops.io/api/billing`
   - Staging: `https://staging.unifyops.io/api/billing`
   - Prod: `https://api.unifyops.io/api/billing`

2. **Backend Service** (dev/staging only):
   - Dev: `https://dev.unifyops.io/service/billing`
   - Staging: `https://staging.unifyops.io/service/billing`

3. **Frontend App**:
   - Dev: `https://billing.dev.unifyops.io`
   - Staging: `https://billing.staging.unifyops.io`
   - Prod: `https://billing.unifyops.io`

## Security Considerations

### Environment Isolation
- Each environment uses different TLS certificates
- Network policies enforce environment boundaries
- Production services are never exposed externally

### Rate Limiting
Applied at the ingress level:
```yaml
annotations:
  nginx.ingress.kubernetes.io/limit-rps: "10"
  nginx.ingress.kubernetes.io/limit-rpm: "100"
```

### CORS Configuration
- Dev: Permissive (`*`)
- Staging: Restricted to staging domains
- Prod: Strictly limited to production domains

## Troubleshooting

### Check Ingress Status
```bash
kubectl get ingress -n uo-dev
kubectl describe ingress auth-api -n uo-dev
```

### Test Internal Routing
```bash
# From inside the cluster
kubectl run test --rm -it --image=curlimages/curl -- sh
curl http://auth-api:8002/api/auth/health
curl http://auth-service:8001/service/auth/health
```

### View Nginx Configuration
```bash
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- cat /etc/nginx/nginx.conf | grep -A5 "location /api/auth"
```

This routing strategy provides a clean, scalable, and secure way to expose your microservices while maintaining consistency across all environments.