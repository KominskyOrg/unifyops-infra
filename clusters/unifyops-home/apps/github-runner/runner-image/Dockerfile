# syntax=docker/dockerfile:1.4
# Minimized GitHub Actions Runner Image for UnifyOps
# Based on the official GitHub Actions runner image
# Includes only tools required by our workflows

# Base image - official GitHub Actions runner
FROM ghcr.io/actions/actions-runner:latest

# Define tool versions as build arguments for easy updates
ARG YQ_VERSION=v4.40.5
ARG KUBECTL_VERSION=v1.29.1
ARG HELM_VERSION=v3.14.0

# Define checksums for verification (update these when changing versions)
ARG YQ_SHA256=0d6aaf1cf44a8d18fbc7ed0ef14f735a8df8d2e314c4cc0f0242d35c0a440c95
ARG KUBECTL_SHA256=69ab3a931e826bf7ac14d38ba7ca637d66a6fcb1ca0e3333a2cafdf15482af9f
ARG HELM_SHA256=f43e1c3387de24547506ab05d24e5309c0ce0b228c23bd8aa64e9ec4b8206651

# Metadata labels (OCI standard)
LABEL org.opencontainers.image.source="https://github.com/KominskyOrg/unifyops-infra"
LABEL org.opencontainers.image.description="Minimized GitHub Actions runner with essential tools for UnifyOps CI/CD"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="UnifyOps"
LABEL maintainer="UnifyOps Team"

# Tool version labels for easy inspection
LABEL yq.version="${YQ_VERSION}"
LABEL kubectl.version="${KUBECTL_VERSION}"
LABEL helm.version="${HELM_VERSION}"

# Switch to root to install packages
USER root

# Install only essential tools in a single layer
# - curl: Download binaries and make HTTP requests
# - git: Git operations (already in base, ensuring version)
# - jq: JSON processing in workflows
# - ca-certificates: HTTPS connections
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    curl=7.* \
    git=1:2.* \
    jq=1.* \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install yq (YAML processor) with version pinning and SHA verification
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -o /tmp/yq && \
    echo "${YQ_SHA256}  /tmp/yq" | sha256sum -c - && \
    install -m 0755 /tmp/yq /usr/local/bin/yq && \
    rm /tmp/yq

# Install kubectl with version pinning and SHA verification
RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /tmp/kubectl && \
    echo "${KUBECTL_SHA256}  /tmp/kubectl" | sha256sum -c - && \
    install -m 0755 /tmp/kubectl /usr/local/bin/kubectl && \
    rm /tmp/kubectl

# Install helm with version pinning and SHA verification
RUN curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tar.gz && \
    echo "${HELM_SHA256}  /tmp/helm.tar.gz" | sha256sum -c - && \
    tar -zxf /tmp/helm.tar.gz -C /tmp && \
    install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm && \
    rm -rf /tmp/helm.tar.gz /tmp/linux-amd64

# Verify installations and create build info file
RUN echo "=== Verifying tool installations ===" && \
    git --version && \
    curl --version && \
    jq --version && \
    yq --version && \
    kubectl version --client && \
    helm version && \
    echo "=== Build completed successfully ===" && \
    # Create build info file
    echo "Build Date: $(date -u +'%Y-%m-%dT%H:%M:%SZ')" > /etc/runner-build-info && \
    echo "yq: ${YQ_VERSION}" >> /etc/runner-build-info && \
    echo "kubectl: ${KUBECTL_VERSION}" >> /etc/runner-build-info && \
    echo "helm: ${HELM_VERSION}" >> /etc/runner-build-info

# Switch back to runner user (base image default)
USER runner
