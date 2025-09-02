#!/bin/bash
# Script to set up GitHub Actions Runner on your cluster

echo "Setting up GitHub Actions Runner on Kubernetes..."

# 1. Install ARC Controller (if not already installed)
echo "Installing Actions Runner Controller..."
helm upgrade --install arc \
  --namespace arc-systems \
  --create-namespace \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --version "0.8.0" \
  --wait

# 2. Create GitHub PAT or App Token
echo ""
echo "You need a GitHub token with these permissions:"
echo "  - For Organization: admin:org, repo"
echo "  - For Repository: repo"
echo ""
echo "Create at: https://github.com/settings/tokens/new"
echo ""
read -p "Enter your GitHub Token: " GITHUB_TOKEN

# 3. Create secret with token
kubectl create namespace github-runners --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic github-token \
  --namespace=github-runners \
  --from-literal=github-token="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. Install runner scale set
echo "Installing runner scale set..."
helm upgrade --install unifyops-runner-set \
  --namespace github-runners \
  --create-namespace \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version "0.8.0" \
  --set githubConfigUrl="https://github.com/KominskyOrg" \
  --set githubConfigSecret="github-token" \
  --set containerMode.type="dind" \
  --set controllerServiceAccount.namespace="arc-systems" \
  --set controllerServiceAccount.name="arc-gha-runner-scale-set-controller" \
  --wait

echo ""
echo "Runner setup complete!"
echo ""
echo "To use in your GitHub Actions workflow, add:"
echo "  runs-on: self-hosted"
echo ""
echo "Check runner status:"
echo "  kubectl get runners -n github-runners"
echo "  kubectl get pods -n github-runners"