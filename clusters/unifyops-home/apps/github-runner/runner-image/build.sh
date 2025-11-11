#!/usr/bin/env bash
#
# Build script for custom GitHub Actions runner image
# Usage: ./build.sh [--push] [--tag TAG]
#
# Options:
#   --push         Push image to Harbor registry after building
#   --tag TAG      Custom tag (default: latest)
#   --no-cache     Build without cache
#   --platform     Target platform (default: linux/amd64)

set -euo pipefail

# Configuration
REGISTRY="harbor.unifyops.io"
PROJECT="library"
IMAGE_NAME="arc-runner-unifyops"
DEFAULT_TAG="latest"

# Parse arguments
PUSH=false
TAG="${DEFAULT_TAG}"
NO_CACHE=""
PLATFORM="linux/amd64"

while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH=true
            shift
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--push] [--tag TAG] [--no-cache] [--platform PLATFORM]"
            echo ""
            echo "Options:"
            echo "  --push         Push image to Harbor registry after building"
            echo "  --tag TAG      Custom tag (default: ${DEFAULT_TAG})"
            echo "  --no-cache     Build without cache"
            echo "  --platform     Target platform (default: linux/amd64)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Full image name
FULL_IMAGE="${REGISTRY}/${PROJECT}/${IMAGE_NAME}:${TAG}"
FULL_IMAGE_SHA="${REGISTRY}/${PROJECT}/${IMAGE_NAME}:$(git rev-parse --short HEAD)"

echo "========================================"
echo "Building Custom GitHub Actions Runner"
echo "========================================"
echo "Image:    ${FULL_IMAGE}"
echo "SHA Tag:  ${FULL_IMAGE_SHA}"
echo "Platform: ${PLATFORM}"
echo "Push:     ${PUSH}"
echo "========================================"
echo ""

# Build with buildkit
export DOCKER_BUILDKIT=1

echo "Building image..."
docker build \
    ${NO_CACHE} \
    --platform "${PLATFORM}" \
    --tag "${FULL_IMAGE}" \
    --tag "${FULL_IMAGE_SHA}" \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --label "build.git.sha=$(git rev-parse HEAD)" \
    --label "build.git.branch=$(git rev-parse --abbrev-ref HEAD)" \
    --label "build.timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    .

echo ""
echo "✅ Build completed successfully!"
echo ""

# Display image info
echo "Image details:"
docker images "${REGISTRY}/${PROJECT}/${IMAGE_NAME}" | head -2
echo ""

# Show tool versions
set +e
echo "Installed tools:"
docker run --rm --entrypoint /bin/sh "${FULL_IMAGE}" -c "
    echo 'yq:      \$(yq --version)'
    echo 'kubectl: \$(kubectl version --client --short 2>/dev/null || kubectl version --client)'
    echo 'helm:    \$(helm version --short)'
    echo 'git:     \$(git --version)'
    echo 'jq:      \$(jq --version)'
" || echo "(Warning: tool check failed, continuing...)"
set -e


# Security scan (if trivy is available)
if command -v trivy &> /dev/null; then
    echo "Running security scan with Trivy..."
    trivy image --severity HIGH,CRITICAL "${FULL_IMAGE}"
    echo ""
fi

# Push if requested
if [ "${PUSH}" = true ]; then
    echo "Pushing image to registry..."
    docker push "${FULL_IMAGE}"
    docker push "${FULL_IMAGE_SHA}"
    echo ""
    echo "✅ Image pushed successfully!"
    echo "   ${FULL_IMAGE}"
    echo "   ${FULL_IMAGE_SHA}"
fi

echo ""
echo "========================================"
echo "Build Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Update app-runners.yaml with the new image:"
echo "   spec.template.spec.containers[0].image: ${FULL_IMAGE}"
echo ""
echo "2. Apply changes via GitOps:"
echo "   git add ."
echo "   git commit -m 'Update runner image to ${TAG}'"
echo "   git push"
echo ""
echo "3. Monitor runner pods:"
echo "   kubectl get pods -n github-runners -w"
echo ""
