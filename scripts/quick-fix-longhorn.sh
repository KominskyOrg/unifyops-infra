#!/bin/bash

echo "🚀 Quick Fix for Longhorn Service Account Issue"
echo "=============================================="

# Apply the service accounts immediately
echo "Creating service accounts..."
kubectl apply -f apps/longhorn/service-accounts.yaml

echo ""
echo "✅ Service accounts created!"
echo ""
echo "Now push changes and apply:"
echo "  git add -A"
echo "  git commit -m 'fix: Add Longhorn service accounts'"
echo "  git push origin main"
echo ""
echo "Then apply the prerequisites app:"
echo "  kubectl apply -f clusters/unifyops-home/apps/longhorn-prerequisites.yaml"
echo ""
echo "The Longhorn pods should now be able to start!"