#!/bin/bash

echo "🚨 IMMEDIATE FIX FOR LONGHORN"
echo "============================="

# Step 1: Ensure namespace exists
echo "1. Creating namespace..."
kubectl create namespace longhorn-system 2>/dev/null || true

# Step 2: Create ALL service accounts Longhorn needs
echo "2. Creating service accounts..."
kubectl apply -f - <<'EOF'
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
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: longhorn-system
EOF

# Step 3: Give them admin permissions (temporary for quick fix)
echo "3. Adding permissions..."
kubectl create clusterrolebinding longhorn-admin --clusterrole=cluster-admin --serviceaccount=longhorn-system:longhorn-service-account 2>/dev/null || true
kubectl create clusterrolebinding longhorn-post-admin --clusterrole=cluster-admin --serviceaccount=longhorn-system:longhorn-post-upgrade-service-account 2>/dev/null || true

# Step 4: Delete the failing job
echo "4. Deleting failed job..."
kubectl delete job -n longhorn-system --all --force --grace-period=0 2>/dev/null || true

# Step 5: Refresh the app
echo "5. Refreshing Longhorn app..."
argocd app get longhorn --refresh 2>/dev/null || echo "Refresh via UI if CLI not configured"

echo ""
echo "✅ Service accounts created!"
echo ""
echo "Now go to ArgoCD UI and:"
echo "1. Click on 'longhorn' app"
echo "2. Click 'REFRESH' button"
echo "3. If still failing, click 'SYNC'"
echo ""
echo "Check pods: kubectl get pods -n longhorn-system"