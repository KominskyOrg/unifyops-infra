#!/bin/bash
set -e

# Production Secrets Creation Script
# WARNING: This script creates secrets directly in the uo-prod namespace
# Secrets will NOT be committed to Git

NAMESPACE="uo-prod"
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BOLD}Production Secrets Creation for UnifyOps Auth Stack${NC}"
echo -e "${YELLOW}⚠️  WARNING: This will create secrets in the ${NAMESPACE} namespace${NC}"
echo ""

# Check if kubectl is connected to the right cluster
CURRENT_CONTEXT=$(kubectl config current-context)
echo -e "Current kubectl context: ${BOLD}${CURRENT_CONTEXT}${NC}"
echo ""

read -p "Are you sure you want to create production secrets? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo -e "${RED}Aborted.${NC}"
    exit 1
fi

echo ""
echo -e "${BOLD}Step 1: Creating JWT Secret${NC}"
echo "Generating strong random JWT secret..."
JWT_SECRET=$(openssl rand -base64 32)

# Check if secret already exists
if kubectl get secret auth-jwt-secret -n $NAMESPACE &> /dev/null; then
    echo -e "${YELLOW}Secret 'auth-jwt-secret' already exists in ${NAMESPACE}${NC}"
    read -p "Do you want to replace it? (yes/no): " REPLACE_JWT
    if [ "$REPLACE_JWT" == "yes" ]; then
        kubectl delete secret auth-jwt-secret -n $NAMESPACE
        kubectl create secret generic auth-jwt-secret \
          --from-literal=jwt-secret="$JWT_SECRET" \
          --namespace=$NAMESPACE
        echo -e "${GREEN}✓ JWT secret replaced${NC}"
    else
        echo -e "${YELLOW}Skipping JWT secret${NC}"
    fi
else
    kubectl create secret generic auth-jwt-secret \
      --from-literal=jwt-secret="$JWT_SECRET" \
      --namespace=$NAMESPACE
    echo -e "${GREEN}✓ JWT secret created${NC}"
fi

echo ""
echo -e "${BOLD}Step 2: Creating Service API Keys${NC}"
echo "Generating service-to-service authentication keys..."
SERVICE_API_KEY=$(openssl rand -hex 32)

if kubectl get secret auth-service-api-keys -n $NAMESPACE &> /dev/null; then
    echo -e "${YELLOW}Secret 'auth-service-api-keys' already exists in ${NAMESPACE}${NC}"
    read -p "Do you want to replace it? (yes/no): " REPLACE_API
    if [ "$REPLACE_API" == "yes" ]; then
        kubectl delete secret auth-service-api-keys -n $NAMESPACE
        kubectl create secret generic auth-service-api-keys \
          --from-literal=auth-service-key="$SERVICE_API_KEY" \
          --namespace=$NAMESPACE
        echo -e "${GREEN}✓ Service API keys replaced${NC}"
    else
        echo -e "${YELLOW}Skipping service API keys${NC}"
    fi
else
    kubectl create secret generic auth-service-api-keys \
      --from-literal=auth-service-key="$SERVICE_API_KEY" \
      --namespace=$NAMESPACE
    echo -e "${GREEN}✓ Service API keys created${NC}"
fi

echo ""
echo -e "${BOLD}Step 3: Verifying Secrets${NC}"
kubectl get secrets -n $NAMESPACE | grep auth

echo ""
echo -e "${GREEN}✓ Production secrets creation complete!${NC}"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: Backup these secrets securely!${NC}"
echo ""
echo "Options for backup:"
echo "1. Store in password manager (1Password, LastPass, etc.)"
echo "2. Export and encrypt with GPG:"
echo "   kubectl get secret auth-jwt-secret -n $NAMESPACE -o yaml > backup.yaml"
echo "   gpg --symmetric --cipher-algo AES256 backup.yaml"
echo ""
echo -e "${YELLOW}⚠️  DO NOT commit these secrets to Git!${NC}"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "1. Backup the secrets securely"
echo "2. Restart deployments to use new secrets:"
echo "   kubectl rollout restart deployment/auth-service -n $NAMESPACE"
echo "   kubectl rollout restart deployment/auth-api -n $NAMESPACE"
echo ""
