#!/bin/bash

# Install ArgoCD CLI if not already installed
if ! command -v argocd &> /dev/null; then
    echo "Installing ArgoCD CLI..."
    brew install argocd
else
    echo "ArgoCD CLI is already installed"
fi

# Get ArgoCD admin password
echo "Getting ArgoCD admin password..."
PW=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)

echo "ArgoCD Admin Password: $PW"

# Login to ArgoCD
echo "Logging into ArgoCD..."
argocd login argocd.local --username admin --password "$PW" --insecure

# List applications
echo "Current ArgoCD Applications:"
argocd app list

echo ""
echo "ArgoCD CLI setup complete!"
echo ""
echo "Useful commands:"
echo "  argocd app list              - List all applications"
echo "  argocd app sync <app-name>   - Manually sync an application"
echo "  argocd app get <app-name>    - Get application details"
echo "  argocd app delete <app-name> - Delete an application"