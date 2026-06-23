FROM debian:bookworm-slim

ARG PACKER_VERSION=1.15.4

# Step 1: Base packages (python3-cryptography installs as dependency here)
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    curl \
    wget \
    software-properties-common \
    unzip \
    jq \
    ca-certificates \
    gnupg \
    apt-transport-https \
    python3 \
    python3-pip \
    netcat-openbsd \
    iproute2 \
    ansible \
    procps \
    python3-winrm \
    && rm -rf /var/lib/apt/lists/*

# Step 2: gcloud (also depends on python3-cryptography — must install BEFORE removing it)
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] \
    https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    google-cloud-sdk \
    && rm -rf /var/lib/apt/lists/*

# Step 3: NOW safe to upgrade cryptography + remove old apt record
# All apt installs are done — no more dependency resolution after this point
# pip installs 49.0.0 to /usr/local/lib/python3.11/ (takes sys.path priority)
# dpkg remove clears the 38.0.4 record so scanner stops flagging it
RUN pip3 install --upgrade 'cryptography>=44.0.0' --break-system-packages \
    && dpkg --remove --force-depends python3-cryptography

# Step 4: Packer with checksum verification
RUN PACKER_ZIP="packer_${PACKER_VERSION}_linux_amd64.zip" && \
    curl -fSL \
        "https://releases.hashicorp.com/packer/${PACKER_VERSION}/${PACKER_ZIP}" \
        -o /tmp/${PACKER_ZIP} && \
    curl -fSL \
        "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_SHA256SUMS" \
        -o /tmp/packer_SHA256SUMS && \
    cd /tmp && grep "${PACKER_ZIP}" packer_SHA256SUMS | sha256sum -c && \
    unzip /tmp/${PACKER_ZIP} -d /usr/local/bin/ && \
    rm -f /tmp/${PACKER_ZIP} /tmp/packer_SHA256SUMS

WORKDIR /workspace
COPY win2022-oracle-client-dev/packer/customize.pkr.hcl ./customize.pkr.hcl
COPY win2022-oracle-client-dev/packer/ansible-playbook/ ./ansible-playbook/
COPY win2022-oracle-client-dev/docker-entrypoint-oracle-client.sh ./docker-entrypoint-oracle-client.sh
RUN chmod +x ./docker-entrypoint-oracle-client.sh && \
    packer init ./customize.pkr.hcl

ENV PACKER_TEMPLATE="customize.pkr.hcl"
ENTRYPOINT ["./docker-entrypoint-oracle-client.sh"]
