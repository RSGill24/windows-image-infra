# ============================================================
# Phase 2: Windows Database Customization Container
# Base: Linux (Debian slim) + Packer + gcloud + DB installer scripts
# Used by Cloud Run Job to customize Phase 1 hardened image with database
# ============================================================

FROM debian:bookworm-slim

ARG PACKER_VERSION=1.9.4
ARG CLOUD_SDK_VERSION=471.0.0

# ── System dependencies ──────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    jq \
    ca-certificates \
    gnupg \
    apt-transport-https \
    python3 \
    ansible \
    procps \
    python3-winrm \
    && rm -rf /var/lib/apt/lists/*

# ── Install Google Cloud SDK ─────────────────────────────────
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] \
    https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    google-cloud-sdk \
    && rm -rf /var/lib/apt/lists/*

# ── Install Packer ───────────────────────────────────────────
RUN curl -fSL \
    "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip" \
    -o /tmp/packer.zip && \
    unzip /tmp/packer.zip -d /usr/local/bin/ && \
    rm -f /tmp/packer.zip && \
    packer version

# ── Working directory ────────────────────────────────────────
WORKDIR /workspace

# ── Copy Packer template ─────────────────────────────────────
COPY packer/customize_db.pkr.hcl ./customize_db.pkr.hcl

# ── Set default Packer template environment variable ──────────
# This ensures the entrypoint script has a sensible default
# Can be overridden at runtime if needed
ENV PACKER_TEMPLATE="customize_db.pkr.hcl"

# ── Create scripts directory (may be empty) ─────────────────────
RUN mkdir -p ./scripts/

# ── Copy Ansible playbooks ─────────────────────────────────────
COPY packer/ansible-playbook/ ./ansible-playbook/

# ── Copy configuration ──────────────────────────────────────────
COPY config.yaml ./config.yaml

# ── Copy entrypoint ─────────────────────────────────────────
COPY docker-entrypoint-phase2.sh ./docker-entrypoint-phase2.sh
RUN chmod +x ./docker-entrypoint-phase2.sh

# ── Copy Ansible playbooks to workspace ────────────────────────
# Already copied above, ensure they're available for Packer

# ── Initialize Packer plugins at build time ──────────────────
RUN packer init ./customize_db.pkr.hcl

# ── Verify all required files exist ────────────────────────────
RUN echo "=== Verifying Phase 2 Container Setup ===" && \
    ls -la config.yaml && \
    ls -la customize_db.pkr.hcl && \
    ls -la docker-entrypoint-phase2.sh && \
    test -d ansible-playbook && echo "✅ Ansible playbooks ready" || echo "⚠️ Ansible playbooks not found" && \
    echo "=== Setup verification complete ===" && \
    pwd && ls -la

# ── Entrypoint ───────────────────────────────────────────────
ENTRYPOINT ["./docker-entrypoint-phase2.sh"]
