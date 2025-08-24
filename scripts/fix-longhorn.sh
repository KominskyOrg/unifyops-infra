#!/bin/bash

echo "🔧 Fixing Longhorn Deployment Issues"
echo "====================================="

# First, ensure the namespace exists
echo "Creating longhorn-system namespace if not exists..."
kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -

# Delete the failed pods to force recreation
echo "Cleaning up failed pods..."
kubectl delete pods -n longhorn-system --all --grace-period=0 --force 2>/dev/null || true

# Sync the Longhorn app again
echo "Re-syncing Longhorn application..."
kubectl patch application longhorn -n argocd --type merge -p '{"spec":{"syncPolicy":{"retry":{"limit":10}}}}'

# Force a sync
echo "Forcing sync..."
argocd app sync longhorn --force || kubectl -n argocd delete application longhorn --cascade=false

echo ""
echo "✅ Fix applied. Longhorn should now retry deployment."
echo ""
echo "Check status with:"
echo "  kubectl get pods -n longhorn-system -w"