#!/usr/bin/env bash
set -euo pipefail

# Local Docker build and push example for Harbor

HARBOR_HOST="${HARBOR_HOST:-harbor.local}"
PROJECT="${PROJECT:-dev}"
IMAGE_NAME="${IMAGE_NAME:-myapp}"
TAG="${TAG:-latest}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Harbor Docker Build & Push Example"
echo "=================================="
echo "Registry: ${HARBOR_HOST}"
echo "Project: ${PROJECT}"
echo "Image: ${IMAGE_NAME}:${TAG}"
echo ""

# Step 1: Login to Harbor
echo -e "${YELLOW}Step 1: Login to Harbor${NC}"
echo "Run: docker login ${HARBOR_HOST}"
echo "Use robot account credentials from apps/harbor/setup/credentials/"
echo ""

# Step 2: Build the image
echo -e "${YELLOW}Step 2: Build Docker image${NC}"
echo "docker build -t ${HARBOR_HOST}/${PROJECT}/${IMAGE_NAME}:${TAG} ."
echo ""

# Step 3: Push to Harbor
echo -e "${YELLOW}Step 3: Push to Harbor${NC}"
echo "docker push ${HARBOR_HOST}/${PROJECT}/${IMAGE_NAME}:${TAG}"
echo ""

# Step 4: Optional - sign the image
echo -e "${YELLOW}Step 4: (Optional) Sign with Cosign${NC}"
echo "cosign sign --yes ${HARBOR_HOST}/${PROJECT}/${IMAGE_NAME}:${TAG}"
echo ""

# Example Kubernetes deployment
echo -e "${GREEN}Example Kubernetes Deployment:${NC}"
cat << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${IMAGE_NAME}
  namespace: ${PROJECT}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${IMAGE_NAME}
  template:
    metadata:
      labels:
        app: ${IMAGE_NAME}
    spec:
      imagePullSecrets:
        - name: harbor-pull
      containers:
        - name: ${IMAGE_NAME}
          image: ${HARBOR_HOST}/${PROJECT}/${IMAGE_NAME}:${TAG}
          imagePullPolicy: Always
          ports:
            - containerPort: 8080
EOF