#!/bin/bash

# Script to mirror Bitnami images from Docker Hub to Harbor registry
# This allows using Bitnami images in an environment with restricted internet access

set -e

# Configuration
HARBOR_REGISTRY="harbor.unifyops.io"
HARBOR_PROJECT="library/bitnami"
DOCKER_REGISTRY="docker.io"

# List of Bitnami images to mirror
IMAGES=(
    "postgresql:16.4.0-debian-12-r13"
    # "postgresql:15.4.0-debian-11-r45"
    # "postgresql:15.4.0"
    # "postgresql:15"
    # "postgresql:latest"
    # "redis:7.2"
    # "redis:latest"
    # "mongodb:7.0"
    # "mongodb:latest"
    # "mysql:8.0"
    # "mysql:latest"
    # "rabbitmq:3.12"
    # "rabbitmq:latest"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "Bitnami Image Mirror Tool"
echo "========================================="
echo ""

# Check if logged into Harbor
echo -e "${YELLOW}Checking Harbor login status...${NC}"
if ! docker info 2>/dev/null | grep -q "$HARBOR_REGISTRY"; then
    echo -e "${YELLOW}Please login to Harbor:${NC}"
    docker login $HARBOR_REGISTRY
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to login to Harbor. Exiting.${NC}"
        exit 1
    fi
fi

# Function to mirror an image
mirror_image() {
    local image=$1
    local source="${DOCKER_REGISTRY}/bitnami/${image}"
    local legacy_source="${DOCKER_REGISTRY}/bitnamilegacy/${image}"
    local target="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${image}"
    local pulled_source=""

    echo ""
    echo -e "${YELLOW}Processing: ${image}${NC}"
    echo "  Target: ${target}"

    # Pull from Docker Hub (try regular repo first, then legacy)
    echo -e "${YELLOW}  Pulling from Docker Hub (AMD64)...${NC}"
    if docker pull --platform linux/amd64 "${source}"; then
        echo -e "${GREEN}  ✓ Pull successful from bitnami${NC}"
        pulled_source="${source}"
    elif docker pull --platform linux/amd64 "${legacy_source}"; then
        echo -e "${GREEN}  ✓ Pull successful from bitnamilegacy${NC}"
        pulled_source="${legacy_source}"
    else
        echo -e "${RED}  ✗ Pull failed from both bitnami and bitnamilegacy${NC}"
        return 1
    fi

    # Tag for Harbor
    echo -e "${YELLOW}  Tagging for Harbor...${NC}"
    if docker tag "${pulled_source}" "${target}"; then
        echo -e "${GREEN}  ✓ Tag successful${NC}"
    else
        echo -e "${RED}  ✗ Tag failed${NC}"
        return 1
    fi

    # Push to Harbor
    echo -e "${YELLOW}  Pushing to Harbor...${NC}"
    if docker push "${target}"; then
        echo -e "${GREEN}  ✓ Push successful${NC}"

        # Clean up local images to save space
        docker rmi "${pulled_source}" 2>/dev/null || true
        docker rmi "${target}" 2>/dev/null || true

        return 0
    else
        echo -e "${RED}  ✗ Push failed${NC}"
        return 1
    fi
}

# Process each image
SUCCESS_COUNT=0
FAILED_COUNT=0
FAILED_IMAGES=()

for image in "${IMAGES[@]}"; do
    if mirror_image "$image"; then
        ((SUCCESS_COUNT++))
    else
        ((FAILED_COUNT++))
        FAILED_IMAGES+=("$image")
    fi
done

# Summary
echo ""
echo "========================================="
echo "Mirror Operation Complete"
echo "========================================="
echo -e "${GREEN}Successful: ${SUCCESS_COUNT}${NC}"
echo -e "${RED}Failed: ${FAILED_COUNT}${NC}"

if [ ${FAILED_COUNT} -gt 0 ]; then
    echo ""
    echo -e "${RED}Failed images:${NC}"
    for failed in "${FAILED_IMAGES[@]}"; do
        echo "  - $failed"
    done
    echo ""
    echo -e "${YELLOW}To retry failed images, run:${NC}"
    echo "  $0"
    exit 1
fi

echo ""
echo -e "${GREEN}All images mirrored successfully!${NC}"
echo ""
echo "You can now use these images in your Kubernetes deployments:"
echo "  ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/postgresql:15.4.0-debian-11-r45"
echo ""
echo "The images will work with your existing Harbor credentials."