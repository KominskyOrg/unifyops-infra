#!/bin/bash

# Script to create JWT secrets for each environment
# These secrets should be created manually in the cluster and NOT committed to Git

set -e

# Function to generate a random JWT secret
generate_jwt_secret() {
    openssl rand -base64 64 | tr -d '\n'
}

# Function to create secret for an environment
create_secret() {
    local namespace=$1
    local secret_name=$2
    local jwt_secret=$3

    echo "Creating secret ${secret_name} in namespace ${namespace}..."

    kubectl create secret generic ${secret_name} \
        --namespace=${namespace} \
        --from-literal=jwt-secret="${jwt_secret}" \
        --dry-run=client -o yaml | kubectl apply -f -

    echo "Secret ${secret_name} created/updated in namespace ${namespace}"
}

# Check if custom JWT secrets are provided via environment variables
DEV_JWT_SECRET=${DEV_JWT_SECRET:-$(generate_jwt_secret)}
STAGING_JWT_SECRET=${STAGING_JWT_SECRET:-$(generate_jwt_secret)}
PROD_JWT_SECRET=${PROD_JWT_SECRET:-$(generate_jwt_secret)}

echo "==================================="
echo "Creating JWT Authentication Secrets"
echo "==================================="
echo ""
echo "NOTE: Save these secrets in a secure password manager!"
echo "They will not be shown again."
echo ""

# Create secrets for each environment
echo "Development Environment:"
echo "  JWT Secret: ${DEV_JWT_SECRET}"
create_secret "uo-dev" "auth-jwt-secret" "${DEV_JWT_SECRET}"
echo ""

echo "Staging Environment:"
echo "  JWT Secret: ${STAGING_JWT_SECRET}"
create_secret "uo-staging" "auth-jwt-secret" "${STAGING_JWT_SECRET}"
echo ""

echo "Production Environment:"
echo "  JWT Secret: ${PROD_JWT_SECRET}"
create_secret "uo-prod" "auth-jwt-secret" "${PROD_JWT_SECRET}"
echo ""

echo "==================================="
echo "Secrets created successfully!"
echo ""
echo "IMPORTANT:"
echo "1. Save the JWT secrets shown above in a secure password manager"
echo "2. These secrets are now in your Kubernetes cluster"
echo "3. DO NOT commit these secrets to Git"
echo "4. The values files have been updated to reference these secrets"
echo ""
echo "To verify the secrets were created:"
echo "  kubectl get secrets -n uo-dev"
echo "  kubectl get secrets -n uo-staging"
echo "  kubectl get secrets -n uo-prod"