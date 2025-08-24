#!/bin/bash

echo "🧹 Force Cleaning Stuck Namespace: longhorn-system"
echo "=================================================="

NAMESPACE="longhorn-system"

# Step 1: Remove finalizers from all Jobs
echo "1. Removing finalizers from Jobs..."
kubectl get jobs -n "$NAMESPACE" -o name | while read job; do
    echo "   Patching $job"
    kubectl patch "$job" -n "$NAMESPACE" --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
done

# Step 2: Force delete all Jobs
echo "2. Force deleting Jobs..."
kubectl delete jobs --all -n "$NAMESPACE" --force --grace-period=0 2>/dev/null || true

# Step 3: Remove finalizers from all remaining resources
echo "3. Removing finalizers from all resources..."
for resource in $(kubectl api-resources --verbs=list --namespaced -o name); do
    kubectl get "$resource" -n "$NAMESPACE" -o name 2>/dev/null | while read item; do
        echo "   Patching $item"
        kubectl patch "$item" -n "$NAMESPACE" --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
    done
done

# Step 4: Remove the namespace finalizer itself
echo "4. Removing namespace finalizer..."
kubectl get namespace "$NAMESPACE" -o json | \
    jq '.spec.finalizers = []' | \
    kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f - 2>/dev/null || true

# Step 5: Final force delete attempt
echo "5. Final cleanup attempt..."
kubectl delete namespace "$NAMESPACE" --force --grace-period=0 2>/dev/null || true

echo ""
echo "✅ Cleanup complete. Checking namespace status..."
kubectl get namespace "$NAMESPACE" 2>/dev/null || echo "Namespace successfully deleted!"

echo ""
echo "Now you can run:"
echo "  ./scripts/reset-longhorn.sh"