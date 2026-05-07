FROM debian:bookworm-slim

ARG PACKER_VERSION=1.9.4

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

RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] \
    https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    google-cloud-sdk \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fSL \
    "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip" \
    -o /tmp/packer.zip && \
    unzip /tmp/packer.zip -d /usr/local/bin/ && \
    rm -f /tmp/packer.zip && \
    packer version

WORKDIR /workspace

COPY win2022-oracle-client-dev/packer/customize_db.pkr.hcl ./customize_db.pkr.hcl

COPY win2022-oracle-client-dev/packer/ansible-playbook/ ./ansible-playbook/

COPY win2022-oracle-client-dev/packer/scripts/config.yaml ./config.yaml

COPY win2022-oracle-client-dev/docker-entrypoint-oracle-client.sh ./docker-entrypoint-oracle-client.sh
RUN chmod +x ./docker-entrypoint-oracle-client.sh

ENV PACKER_TEMPLATE="customize_db.pkr.hcl"

RUN packer init ./customize_db.pkr.hcl

RUN echo "=== Verifying Container Setup ===" && \
    ls -la config.yaml && \
    ls -la customize_db.pkr.hcl && \
    ls -la docker-entrypoint-oracle-client.sh && \
    test -d ansible-playbook && echo "Ansible playbooks ready" || echo "Ansible playbooks not found" && \
    echo "=== Setup verification complete ===" && \
    pwd && ls -la

ENTRYPOINT ["./docker-entrypoint-oracle-client.sh"]
