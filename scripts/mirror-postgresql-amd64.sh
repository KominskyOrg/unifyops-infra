#!/bin/bash

# Script to mirror PostgreSQL image for AMD64 architecture specifically

set -e

# Configuration
HARBOR_REGISTRY="harbor.unifyops.io"
HARBOR_PROJECT="library/bitnami"
SOURCE_IMAGE="docker.io/bitnami/postgresql:15.4.0-debian-11-r45"
TARGET_IMAGE="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/postgresql:15.4.0-debian-11-r45"

echo "========================================="
echo "PostgreSQL Image Mirror to Harbor (AMD64)"
echo "========================================="
echo ""
echo "Source: ${SOURCE_IMAGE} (amd64 platform)"
echo "Target: ${TARGET_IMAGE}"
echo ""

# Check Docker status
echo "Checking Docker status..."
if ! docker info > /dev/null 2>&1; then
    echo "✗ Docker is not running"
    echo "Please start Docker Desktop and run this script again"
    exit 1
fi
echo "✓ Docker is running"

# Login to Harbor if needed
echo ""
echo "Checking Harbor login..."
if docker pull ${HARBOR_REGISTRY}/library/busybox:latest > /dev/null 2>&1; then
    echo "✓ Already logged into Harbor"
else
    echo "Logging into Harbor..."
    docker login ${HARBOR_REGISTRY}
fi

# Pull the AMD64 version explicitly
echo ""
echo "Step 1: Pulling PostgreSQL image for AMD64 platform..."
docker pull --platform linux/amd64 ${SOURCE_IMAGE}

# Tag for Harbor
echo ""
echo "Step 2: Tagging image for Harbor..."
docker tag ${SOURCE_IMAGE} ${TARGET_IMAGE}

# Push to Harbor (will push the amd64 version)
echo ""
echo "Step 3: Pushing AMD64 image to Harbor..."
docker push ${TARGET_IMAGE}

# Verify the pushed image
echo ""
echo "Step 4: Verifying pushed image..."
docker manifest inspect ${TARGET_IMAGE} 2>/dev/null | grep -A 2 architecture | head -5 || echo "Unable to verify manifest"

# Clean up local images to save space
echo ""
echo "Step 5: Cleaning up local images..."
docker rmi ${SOURCE_IMAGE} || true
docker rmi ${TARGET_IMAGE} || true

echo ""
echo "========================================="
echo "✓ Success!"
echo "========================================="
echo ""
echo "The PostgreSQL AMD64 image is now available in your Harbor registry:"
echo "  ${TARGET_IMAGE}"
echo ""
echo "Your AMD64 Kubernetes nodes will now be able to pull and run this image."