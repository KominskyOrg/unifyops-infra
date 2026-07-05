# syntax=docker/dockerfile:1.4

######################################################################
# UnifyOps GitHub Actions Runner (Hardened)
# Base: official ghcr.io/actions/actions-runner image
# Adds essential CI tools: kubectl, helm, yq, jq, git, curl
# Verified via SHA256 and pinned versions
######################################################################

# --------------------------------------------------------------------
# Base image (official GitHub Actions runner)
# --------------------------------------------------------------------
    FROM ghcr.io/actions/actions-runner:latest

    # --------------------------------------------------------------------
    # Metadata and Labels (OCI-compliant)
    # --------------------------------------------------------------------
    LABEL org.opencontainers.image.title="UnifyOps ARC Runner" \
          org.opencontainers.image.description="Hardened GitHub Actions runner image with Kubernetes and Helm tools for UnifyOps CI/CD." \
          org.opencontainers.image.source="https://github.com/KominskyOrg/unifyops-infra" \
          org.opencontainers.image.vendor="UnifyOps" \
          org.opencontainers.image.licenses="MIT" \
          maintainer="platform@unifyops.io"
    
    # --------------------------------------------------------------------
    # Tool versions and checksums (update here as needed)
    # --------------------------------------------------------------------
    ARG YQ_VERSION=v4.40.5
    ARG KUBECTL_VERSION=v1.29.1
    ARG HELM_VERSION=v3.14.0
    
    ARG YQ_SHA256=0d6aaf1cf44a8d18fbc7ed0ef14f735a8df8d2e314c4cc0f0242d35c0a440c95
    ARG KUBECTL_SHA256=69ab3a931e826bf7ac14d38ba7ca637d66a6fcb1ca0e3333a2cafdf15482af9f
    # helm comes from the digest-pinned alpine/helm image (see below), not get.helm.sh
    
    # --------------------------------------------------------------------
    # Environment configuration
    # --------------------------------------------------------------------
    ENV DEBIAN_FRONTEND=noninteractive \
        PATH="/usr/local/bin:/usr/bin:/bin:/actions-runner:${PATH}"
    
    # --------------------------------------------------------------------
    # Install core dependencies with caching and cleanup
    # --------------------------------------------------------------------
    USER root
    
    RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
        --mount=type=cache,target=/var/lib/apt,sharing=locked \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            ca-certificates \
            curl=8.* \
            git=1:2.* \
            jq=1.* \
            tar \
            gzip \
        && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
    
    # --------------------------------------------------------------------
    # Install yq (YAML processor)
    # --------------------------------------------------------------------
    RUN curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -o /usr/local/bin/yq && \
        echo "${YQ_SHA256}  /usr/local/bin/yq" | sha256sum -c - && \
        chmod +x /usr/local/bin/yq
    
    # --------------------------------------------------------------------
    # Install kubectl
    # --------------------------------------------------------------------
    RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl && \
        echo "${KUBECTL_SHA256}  /usr/local/bin/kubectl" | sha256sum -c - && \
        chmod +x /usr/local/bin/kubectl
    
    # --------------------------------------------------------------------
    # Install helm
    # --------------------------------------------------------------------
    # get.helm.sh (Fastly) hard-resets large transfers from this cluster
    # (8 retries with resume all reset — runs 28745978239/28746282690/28746475021),
    # so take the binary from the official alpine/helm image on Docker Hub,
    # pinned by digest for integrity. Digest is for tag 3.14.0 (= HELM_VERSION).
    COPY --from=alpine/helm:3.14.0@sha256:a90798c9c2b671e3546b10db1ae0b845f9abccc9f9ff79b34744a1ba146b67ed \
        /usr/bin/helm /usr/local/bin/helm
    RUN helm version --short
    
    # --------------------------------------------------------------------
    # Security Hardening
    # --------------------------------------------------------------------
    # Remove setuid/setgid bits and unnecessary binaries
    RUN find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -exec chmod a-s {} + || true
    
    # Create a build info manifest for traceability
    RUN echo "Build Date: $(date -u +'%Y-%m-%dT%H:%M:%SZ')" > /etc/runner-build-info && \
        echo "yq: ${YQ_VERSION}" >> /etc/runner-build-info && \
        echo "kubectl: ${KUBECTL_VERSION}" >> /etc/runner-build-info && \
        echo "helm: ${HELM_VERSION}" >> /etc/runner-build-info
    
    # --------------------------------------------------------------------
    # Return to non-root user (runner)
    # --------------------------------------------------------------------
    USER runner

    # --------------------------------------------------------------------
    # Directly run the GitHub Actions runner binary
    # ARC injects configuration and environment on startup
    # --------------------------------------------------------------------
    ENTRYPOINT ["/home/runner/bin/Runner.Listener"]
    CMD ["run", "--startuptype", "service"]