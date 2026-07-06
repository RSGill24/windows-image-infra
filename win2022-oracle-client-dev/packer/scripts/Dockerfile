FROM debian:bookworm-slim

ARG PACKER_VERSION=1.9.4

# ── System packages ────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    software-properties-common \
    unzip \
    jq \
    ca-certificates \
    gnupg \
    apt-transport-https \
    python3 \
    netcat-openbsd \
    iproute2 \
    ansible \
    procps \
    python3-winrm \
    && rm -rf /var/lib/apt/lists/*

# ── Google Cloud SDK ──────────────────────────────────────────────────────────
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] \
    https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    google-cloud-sdk \
    && rm -rf /var/lib/apt/lists/*

# ── Packer ─────────────────────────────────────────────────────────────────────
RUN curl -fSL \
    "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip" \
    -o /tmp/packer.zip && \
    unzip /tmp/packer.zip -d /usr/local/bin/ && \
    rm -f /tmp/packer.zip

WORKDIR /workspace

# ── Copy artefacts ─────────────────────────────────────────────────────────────
COPY win2022-oracle-client-dev/packer/customize.pkr.hcl          ./customize.pkr.hcl
COPY win2022-oracle-client-dev/packer/ansible-playbook/           ./ansible-playbook/
COPY win2022-oracle-client-dev/docker-entrypoint.sh               ./docker-entrypoint.sh

RUN chmod +x ./docker-entrypoint.sh && \
    packer init ./customize.pkr.hcl

# Default template path (can be overridden via Cloud Run env var)
ENV PACKER_TEMPLATE="customize.pkr.hcl"

# ── Default component flags (all off; override in Cloud Run / Terraform / JSON) ─
ENV INSTALL_ORACLE="false"
ENV INSTALL_RSTUDIO="false"
ENV INSTALL_CONDA="false"
ENV INSTALL_CHROME="false"
ENV INSTALL_GIT="false"
ENV INSTALL_PYTHON="false"
ENV INSTALL_JUPYTERLAB="false"
ENV INSTALL_POWERSHELL_CORE="false"
ENV INSTALL_PYCHARM="false"
ENV INSTALL_VISUAL_STUDIO="false"
ENV INSTALL_PARAVIEW="false"
ENV INSTALL_ECHOVIEW="false"
ENV INSTALL_MATLAB="false"
ENV INSTALL_RSTUDIO_PRO="false"
ENV INSTALL_POSITRON="false"
ENV INSTALL_ANACONDA="false"
ENV INSTALL_GPU_DRIVERS="false"
ENV INSTALL_AALIBRARY="false"
ENV INSTALL_ECHOSMS="false"
ENV INSTALL_ECHOSTACK="false"
ENV INSTALL_GCP_UTILITIES="false"
ENV INSTALL_EXCEL="false"

# ── JSON mode config (set by Eventarc trigger) ────────────────────────────────
ENV REQUEST_JSON_GCS=""
ENV GCS_STATUS_BUCKET=""

ENTRYPOINT ["./docker-entrypoint.sh"]
