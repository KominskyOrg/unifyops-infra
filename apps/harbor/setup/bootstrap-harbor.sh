#!/usr/bin/env bash
set -euo pipefail

# Harbor Bootstrap Script - Sets up projects and robot accounts
# Run this after Harbor is deployed and accessible

HARBOR_HOST="${HARBOR_HOST:-harbor.local}"
HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD:-Harbor12345!}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Harbor Bootstrap Configuration${NC}"
echo "=============================="
echo "Harbor URL: https://${HARBOR_HOST}"
echo ""

# Wait for Harbor to be ready
echo "Checking Harbor availability..."
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -k -s "https://${HARBOR_HOST}/api/v2.0/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Harbor is accessible${NC}"
        break
    fi
    echo "Waiting for Harbor to be ready... ($((RETRY_COUNT+1))/$MAX_RETRIES)"
    sleep 10
    RETRY_COUNT=$((RETRY_COUNT+1))
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${RED}✗ Harbor is not accessible after ${MAX_RETRIES} attempts${NC}"
    exit 1
fi

# Function to create project
create_project() {
    local project_name=$1
    echo -e "\n${YELLOW}Creating project: ${project_name}${NC}"
    
    curl -k -X POST "https://${HARBOR_HOST}/api/v2.0/projects" \
        -H "Content-Type: application/json" \
        -u "admin:${HARBOR_ADMIN_PASSWORD}" \
        -d '{
            "project_name": "'${project_name}'",
            "public": false,
            "metadata": {
                "auto_scan": "true",
                "severity": "high",
                "prevent_vul": "false",
                "enable_content_trust": "false"
            }
        }' 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Project ${project_name} created${NC}"
    else
        echo -e "${YELLOW}! Project ${project_name} may already exist${NC}"
    fi
}

# Function to create robot account
create_robot_account() {
    local project_name=$1
    local robot_name="robot\$${project_name}_ci"
    
    echo -e "\n${YELLOW}Creating robot account: ${robot_name}${NC}"
    
    # Get project ID
    PROJECT_ID=$(curl -k -s "https://${HARBOR_HOST}/api/v2.0/projects?name=${project_name}" \
        -u "admin:${HARBOR_ADMIN_PASSWORD}" | jq -r '.[0].project_id')
    
    if [ "$PROJECT_ID" == "null" ] || [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}✗ Failed to get project ID for ${project_name}${NC}"
        return 1
    fi
    
    # Create robot account
    RESPONSE=$(curl -k -s -X POST "https://${HARBOR_HOST}/api/v2.0/robots" \
        -H "Content-Type: application/json" \
        -u "admin:${HARBOR_ADMIN_PASSWORD}" \
        -d '{
            "name": "'${robot_name}'",
            "duration": -1,
            "description": "CI/CD robot account for '${project_name}' environment",
            "disable": false,
            "level": "project",
            "permissions": [
                {
                    "namespace": "'${project_name}'",
                    "kind": "project",
                    "access": [
                        {
                            "resource": "repository",
                            "action": "push"
                        },
                        {
                            "resource": "repository",
                            "action": "pull"
                        },
                        {
                            "resource": "tag",
                            "action": "create"
                        },
                        {
                            "resource": "tag",
                            "action": "delete"
                        },
                        {
                            "resource": "artifact",
                            "action": "read"
                        },
                        {
                            "resource": "artifact",
                            "action": "list"
                        }
                    ]
                }
            ]
        }')
    
    # Extract token
    TOKEN=$(echo "$RESPONSE" | jq -r '.secret')
    
    if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ]; then
        echo -e "${GREEN}✓ Robot account created${NC}"
        echo -e "${BLUE}  Username: ${robot_name}${NC}"
        echo -e "${BLUE}  Token: ${TOKEN}${NC}"
        
        # Save to file
        mkdir -p apps/harbor/setup/credentials
        echo "${TOKEN}" > "apps/harbor/setup/credentials/${project_name}_robot_token.txt"
        echo -e "${GREEN}  Token saved to: apps/harbor/setup/credentials/${project_name}_robot_token.txt${NC}"
    else
        echo -e "${YELLOW}! Robot account may already exist${NC}"
    fi
}

# Create projects
echo -e "\n${BLUE}Step 1: Creating Projects${NC}"
echo "========================="
for project in dev staging prod; do
    create_project $project
done

# Create robot accounts
echo -e "\n${BLUE}Step 2: Creating Robot Accounts${NC}"
echo "================================"
for project in dev staging prod; do
    create_robot_account $project
done

# Generate secret manifests
echo -e "\n${BLUE}Step 3: Generating Kubernetes Secrets${NC}"
echo "===================================="
mkdir -p apps/harbor/setup/secrets

for env in dev staging prod; do
    if [ -f "apps/harbor/setup/credentials/${env}_robot_token.txt" ]; then
        TOKEN=$(cat "apps/harbor/setup/credentials/${env}_robot_token.txt")
        ROBOT_NAME="robot\$${env}_ci"
        
        # Base64 encode for dockerconfigjson
        AUTH=$(echo -n "${ROBOT_NAME}:${TOKEN}" | base64)
        DOCKERCONFIG=$(echo -n '{"auths":{"'${HARBOR_HOST}'":{"username":"'${ROBOT_NAME}'","password":"'${TOKEN}'","auth":"'${AUTH}'"}}}' | base64)
        
        cat > "apps/harbor/setup/secrets/harbor-pull-secret-${env}.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: harbor-pull
  namespace: ${env}
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: ${DOCKERCONFIG}
EOF
        echo -e "${GREEN}✓ Generated secret for ${env} namespace${NC}"
    fi
done

echo -e "\n${GREEN}Harbor Bootstrap Complete!${NC}"
echo "========================="
echo ""
echo "Next steps:"
echo "1. Apply the secrets to your namespaces:"
echo "   kubectl apply -f apps/harbor/setup/secrets/"
echo ""
echo "2. Update your deployments to use Harbor:"
echo "   - Image: ${HARBOR_HOST}/<project>/<repo>:<tag>"
echo "   - ImagePullSecret: harbor-pull"
echo ""
echo "3. Configure your CI/CD with the robot tokens in:"
echo "   apps/harbor/setup/credentials/"
echo ""
echo "4. Access Harbor UI at: https://${HARBOR_HOST}"
echo "   Username: admin"
echo "   Password: ${HARBOR_ADMIN_PASSWORD}