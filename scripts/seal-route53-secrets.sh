#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Route53 Credentials Sealing Script ==="
echo ""

# Check if kubeseal is installed
if ! command -v kubeseal &> /dev/null; then
    echo "Error: kubeseal is not installed"
    exit 1
fi

# Fetch the sealing certificate
echo "Fetching sealing certificate from cluster..."
kubeseal --controller-name=sealed-secrets --controller-namespace=sealed-secrets --fetch-cert > /tmp/pub-cert.pem
echo "✓ Sealing certificate fetched"
echo ""

# Function to seal a secret from a namespace
seal_secret() {
    local namespace=$1
    local secret_name=$2
    local output_file=$3

    echo "Processing $namespace/$secret_name..."

    if ! kubectl get secret "$secret_name" -n "$namespace" &> /dev/null; then
        echo "⚠ Secret $secret_name not found in namespace $namespace, skipping..."
        return
    fi

    kubectl get secret "$secret_name" -n "$namespace" -o yaml | \
        kubeseal --controller-name=sealed-secrets --controller-namespace=sealed-secrets \
        --cert /tmp/pub-cert.pem --format yaml > "$output_file"

    echo "✓ Sealed secret created: $output_file"
}

# Seal secrets
mkdir -p "$REPO_ROOT/clusters/unifyops-home/apps/cert-manager/secrets"
mkdir -p "$REPO_ROOT/clusters/unifyops-home/apps/harbor/secrets"
mkdir -p "$REPO_ROOT/clusters/unifyops-home/apps/longhorn/secrets"
mkdir -p "$REPO_ROOT/clusters/unifyops-home/apps/external-dns/secrets"

echo "=== Sealing cert-manager/route53-credentials ==="
seal_secret "cert-manager" "route53-credentials" \
    "$REPO_ROOT/clusters/unifyops-home/apps/cert-manager/secrets/route53-credentials.sealed.yaml"
echo ""

echo "=== Sealing harbor-system/route53-credentials ==="
seal_secret "harbor-system" "route53-credentials" \
    "$REPO_ROOT/clusters/unifyops-home/apps/harbor/secrets/route53-credentials.sealed.yaml"
echo ""

echo "=== Sealing longhorn-system/route53-credentials ==="
seal_secret "longhorn-system" "route53-credentials" \
    "$REPO_ROOT/clusters/unifyops-home/apps/longhorn/secrets/route53-credentials.sealed.yaml"
echo ""

echo "=== Sealing uo-infra/externaldns-aws ==="
seal_secret "uo-infra" "externaldns-aws" \
    "$REPO_ROOT/clusters/unifyops-home/apps/external-dns/secrets/externaldns-aws-sealed.yaml"
echo ""

rm -f /tmp/pub-cert.pem

echo "=== Summary ==="
echo "✓ All secrets sealed successfully!"
