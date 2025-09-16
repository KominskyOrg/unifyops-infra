#!/bin/bash

# Script to create PostgreSQL secrets for each environment
# These secrets should be created manually in the cluster and NOT committed to Git

set -e

# Function to generate a random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Function to create secret for an environment
create_secret() {
    local namespace=$1
    local secret_name=$2
    local postgres_password=$3
    local user_password=$4

    echo "Creating secret ${secret_name} in namespace ${namespace}..."

    kubectl create secret generic ${secret_name} \
        --namespace=${namespace} \
        --from-literal=postgres-password="${postgres_password}" \
        --from-literal=password="${user_password}" \
        --from-literal=replication-password="${postgres_password}" \
        --dry-run=client -o yaml | kubectl apply -f -

    echo "Secret ${secret_name} created/updated in namespace ${namespace}"
}

# Check if custom passwords are provided via environment variables
DEV_POSTGRES_PASSWORD=${DEV_POSTGRES_PASSWORD:-$(generate_password)}
DEV_USER_PASSWORD=${DEV_USER_PASSWORD:-$(generate_password)}

STAGING_POSTGRES_PASSWORD=${STAGING_POSTGRES_PASSWORD:-$(generate_password)}
STAGING_USER_PASSWORD=${STAGING_USER_PASSWORD:-$(generate_password)}

PROD_POSTGRES_PASSWORD=${PROD_POSTGRES_PASSWORD:-$(generate_password)}
PROD_USER_PASSWORD=${PROD_USER_PASSWORD:-$(generate_password)}

echo "==================================="
echo "Creating PostgreSQL Database Secrets"
echo "==================================="
echo ""
echo "NOTE: Save these passwords in a secure password manager!"
echo "They will not be shown again."
echo ""

# Create secrets for each environment
echo "Development Environment:"
echo "  Postgres Password: ${DEV_POSTGRES_PASSWORD}"
echo "  User Password: ${DEV_USER_PASSWORD}"
create_secret "uo-dev" "auth-postgresql-secret" "${DEV_POSTGRES_PASSWORD}" "${DEV_USER_PASSWORD}"
echo ""

echo "Staging Environment:"
echo "  Postgres Password: ${STAGING_POSTGRES_PASSWORD}"
echo "  User Password: ${STAGING_USER_PASSWORD}"
create_secret "uo-staging" "auth-postgresql-secret" "${STAGING_POSTGRES_PASSWORD}" "${STAGING_USER_PASSWORD}"
echo ""

echo "Production Environment:"
echo "  Postgres Password: ${PROD_POSTGRES_PASSWORD}"
echo "  User Password: ${PROD_USER_PASSWORD}"
create_secret "uo-prod" "auth-postgresql-secret" "${PROD_POSTGRES_PASSWORD}" "${PROD_USER_PASSWORD}"
echo ""

echo "==================================="
echo "Secrets created successfully!"
echo ""
echo "IMPORTANT:"
echo "1. Save the passwords shown above in a secure password manager"
echo "2. These secrets are now in your Kubernetes cluster"
echo "3. DO NOT commit these passwords to Git"
echo "4. Update your values files to reference these secrets"
echo ""
echo "To verify the secrets were created:"
echo "  kubectl get secrets -n uo-dev"
echo "  kubectl get secrets -n uo-staging"
echo "  kubectl get secrets -n uo-prod"