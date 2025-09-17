#!/bin/bash

# Quick script to mirror just the PostgreSQL image we need

set -e

# Configuration
HARBOR_REGISTRY="harbor.unifyops.io"
HARBOR_PROJECT="library/bitnami"
SOURCE_IMAGE="docker.io/bitnami/postgresql:15.4.0-debian-11-r45"
TARGET_IMAGE="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/postgresql:15.4.0-debian-11-r45"

echo "========================================="
echo "PostgreSQL Image Mirror to Harbor"
echo "========================================="
echo ""
echo "Source: ${SOURCE_IMAGE}"
echo "Target: ${TARGET_IMAGE}"
echo ""

# Wait for Docker to be ready
echo "Checking Docker status..."
for i in {1..30}; do
    if docker info > /dev/null 2>&1; then
        echo "✓ Docker is running"
        break
    else
        if [ $i -eq 30 ]; then
            echo "✗ Docker is not running after 30 seconds"
            echo "Please start Docker Desktop and run this script again"
            exit 1
        fi
        echo "Waiting for Docker to start... ($i/30)"
        sleep 1
    fi
done

# Login to Harbor if needed
echo ""
echo "Logging into Harbor..."
echo "Note: Use your Harbor credentials (same as when you pull images)"
docker login ${HARBOR_REGISTRY}

# Pull from Docker Hub
echo ""
echo "Step 1: Pulling PostgreSQL image from Docker Hub..."
docker pull ${SOURCE_IMAGE}

# Tag for Harbor
echo ""
echo "Step 2: Tagging image for Harbor..."
docker tag ${SOURCE_IMAGE} ${TARGET_IMAGE}

# Push to Harbor
echo ""
echo "Step 3: Pushing image to Harbor..."
docker push ${TARGET_IMAGE}

# Clean up local images to save space
echo ""
echo "Step 4: Cleaning up local images..."
docker rmi ${SOURCE_IMAGE} || true
docker rmi ${TARGET_IMAGE} || true

echo ""
echo "========================================="
echo "✓ Success!"
echo "========================================="
echo ""
echo "The PostgreSQL image is now available in your Harbor registry:"
echo "  ${TARGET_IMAGE}"
echo ""
echo "Your pods will now be able to pull this image using the existing Harbor credentials."
echo ""
echo "Next step: The pods should automatically restart and pull the image from Harbor."