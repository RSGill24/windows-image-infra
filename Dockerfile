# ============================================================
# Windows Packer Builder Container
# Base: Linux (Debian slim) + Packer + gcloud + PS scripts
# Used by Cloud Run Job to build STIG-hardened Windows GCE image
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
COPY packer/harden_ww.pkr.hcl ./harden_ww.pkr.hcl

# ── Copy hardening scripts ───────────────────────────────────
COPY packer/scripts/ ./scripts/

# ── Copy entrypoint ─────────────────────────────────────────
COPY docker-entrypoint.sh ./docker-entrypoint.sh
RUN chmod +x ./docker-entrypoint.sh

# ── Initialize Packer plugins at build time ──────────────────
RUN packer init ./harden_ww.pkr.hcl

# ── Entrypoint ───────────────────────────────────────────────
ENTRYPOINT ["./docker-entrypoint.sh"]