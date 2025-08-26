#!/usr/bin/env bash
set -euo pipefail


kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -


# Official stable install manifest
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml


echo "Waiting for Argo CD pods..."
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s || true
kubectl -n argocd get pods -o wide


echo "Argo CD installed. To get initial admin password:"
echo "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"