# ============================================================
# Windows Packer Builder Container
# Base: Linux (Debian slim) + Packer + gcloud + PS scripts
# Used by Cloud Run Job to build STIG-hardened Windows GCE image
# ============================================================

FROM debian:bookworm-slim

ARG PACKER_VERSION=1.9.4

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
    && rm -rf /var/lib/apt/lists/*

# ── Install Google Cloud CLI ─────────────────────────────────
# Package name is google-cloud-cli, NOT google-cloud-sdk.
# Google retired the google-cloud-sdk name; the repo still serves the
# cloud-sdk distro but no longer publishes a package under the old name:
#   google-cloud-sdk:  Candidate: (none)     <- build fails with exit 100
#   google-cloud-cli:  Candidate: 583.0.0-0
# An image built before the retirement keeps working, so this only surfaces
# on the next rebuild: "Package 'google-cloud-sdk' has no installation candidate".
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] \
    https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

# Do NOT invoke gcloud during the image build.
#
# gcloud caches whether it is running on GCE in ~/.config/gcloud/gce. A build
# runs in Cloud Build, where the GCE metadata probe fails, so any build-time
# gcloud call writes "False" there -- and that file ships inside the image.
# At runtime in Cloud Run, gcloud then trusts the cached "False", never asks the
# metadata server for credentials, and every command fails with:
#   ERROR: (gcloud.compute.start-iap-tunnel) Your current active account
#          [...] does not have any valid credentials
# which surfaces as a Packer "Non-retryable tunnel error".
#
# Removing the directory outright means the first runtime call re-detects GCE
# correctly. docker-entrypoint.sh also clears it defensively at startup.
RUN rm -rf /root/.config/gcloud

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
