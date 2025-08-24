#!/bin/bash
set -e

echo "🚀 Applying ArgoCD Configuration..."
echo "=================================="

# Apply ArgoCD Projects
echo ""
echo "📁 Applying ArgoCD Projects..."
kubectl apply -f projects/infra.yaml
kubectl apply -f projects/dev.yaml
kubectl apply -f projects/staging.yaml
kubectl apply -f projects/prod.yaml

# Apply Repository Secrets
echo ""
echo "🔐 Registering repositories in ArgoCD..."
kubectl apply -f argocd/repo-secrets.yaml

# Apply the root app-of-apps
echo ""
echo "🎯 Applying root app-of-apps..."
kubectl apply -f clusters/unifyops-home/bootstrap/root-app.yaml

echo ""
echo "✅ ArgoCD configuration applied successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Check ArgoCD UI at: http://argocd.local"
echo "2. Apps should start syncing automatically"
echo "3. Run './scripts/setup-argocd-cli.sh' to setup CLI access"
echo ""
echo "🔍 To check application status:"
echo "   kubectl get applications -n argocd"
echo ""
echo "🔄 To manually sync all apps:"
echo "   argocd app sync -l argocd.argoproj.io/instance=root-app"