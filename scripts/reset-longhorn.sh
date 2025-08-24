#!/bin/bash
set -e

echo "🔄 Resetting Longhorn Deployment"
echo "================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${YELLOW}This will completely reset Longhorn deployment${NC}"
echo ""

# Step 1: Delete the Longhorn application
echo "1. Deleting Longhorn application from ArgoCD..."
kubectl delete application longhorn -n argocd --ignore-not-found=true

# Step 2: Clean up namespace
echo "2. Cleaning up longhorn-system namespace..."
kubectl delete namespace longhorn-system --ignore-not-found=true --wait=false

# Step 3: Wait for namespace deletion
echo "3. Waiting for namespace cleanup (may take a minute)..."
kubectl wait --for=delete namespace/longhorn-system --timeout=60s 2>/dev/null || true

# Step 4: Recreate namespace with proper labels
echo "4. Creating fresh longhorn-system namespace..."
kubectl create namespace longhorn-system
kubectl label namespace longhorn-system name=longhorn-system

# Step 5: Pre-create service account to avoid race condition
echo "5. Pre-creating service account..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: longhorn-service-account
  namespace: longhorn-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: longhorn-post-upgrade-service-account
  namespace: longhorn-system
EOF

# Step 6: Reapply the Longhorn application
echo "6. Reapplying Longhorn application..."
kubectl apply -f clusters/unifyops-home/apps/longhorn.yaml

echo ""
echo -e "${GREEN}✅ Longhorn reset complete!${NC}"
echo ""
echo "Monitor deployment with:"
echo "  kubectl get pods -n longhorn-system -w"
echo ""
echo "Check application status:"
echo "  kubectl get application longhorn -n argocd"
echo ""
echo "If issues persist, check:"
echo "  kubectl describe pods -n longhorn-system"
echo "  kubectl get events -n longhorn-system --sort-by='.lastTimestamp'"