#!/usr/bin/env bash
set -euo pipefail

echo "Phase 2: Oracle Client Image Builder — $(date -u)"
packer version

PROJECT_ID="big-mender-473219-r2"
SOURCE_IMAGE_PROJECT_ID="big-mender-473219-r2"

# NAMING CONVENTION: picks up Phase 1 output — nmfs-[os]-[version]
SOURCE_IMAGE_FAMILY="nmfs-windows-2022"

# NAMING CONVENTION: nmfs-[os]-[version]-[purpose]
IMAGE_FAMILY="nmfs-windows-2022"

ZONE="us-east4-b"
MACHINE_TYPE="e2-standard-8"
SERVICE_ACCOUNT_EMAIL="packer-win-sa@big-mender-473219-r2.iam.gserviceaccount.com"
WINRM_SECRET="packer-winrm-password"
INSTALLATION_TARGET_DIR="C:/Users/packer_user/installation/"
INSTALLATION_SOURCE_DIR="./ansible-playbook"
PACKER_TEMPLATE="customize.pkr.hcl"

PACKER_PW=$(gcloud secrets versions access latest \
  --project "${PROJECT_ID}" \
  --secret "${WINRM_SECRET}")
export PACKER_PW
export PACKER_LOG=1
export PACKER_LOG_PATH="/tmp/packer-debug.log"

if [ ! -f "${PACKER_TEMPLATE}" ]; then
  echo "[ERROR] Packer template not found: ${PACKER_TEMPLATE}"
  exit 1
fi

packer init "${PACKER_TEMPLATE}"

packer validate \
  -var "project_id=${PROJECT_ID}" \
  -var "source_image_project_id=${SOURCE_IMAGE_PROJECT_ID}" \
  -var "source_image_family=${SOURCE_IMAGE_FAMILY}" \
  -var "service_account_email=${SERVICE_ACCOUNT_EMAIL}" \
  -var "image_family=${IMAGE_FAMILY}" \
  -var "machine_type=${MACHINE_TYPE}" \
  -var "zone=${ZONE}" \
  -var "installation_source_dir=${INSTALLATION_SOURCE_DIR}" \
  -var "installation_target_dir=${INSTALLATION_TARGET_DIR}" \
  "${PACKER_TEMPLATE}"

if ! gcloud auth list 2>&1 | grep -q "ACTIVE"; then
  echo "[ERROR] gcloud is not authenticated"
  exit 1
fi

if ! packer build \
  -var "project_id=${PROJECT_ID}" \
  -var "source_image_project_id=${SOURCE_IMAGE_PROJECT_ID}" \
  -var "source_image_family=${SOURCE_IMAGE_FAMILY}" \
  -var "service_account_email=${SERVICE_ACCOUNT_EMAIL}" \
  -var "image_family=${IMAGE_FAMILY}" \
  -var "machine_type=${MACHINE_TYPE}" \
  -var "zone=${ZONE}" \
  -var "installation_source_dir=${INSTALLATION_SOURCE_DIR}" \
  -var "installation_target_dir=${INSTALLATION_TARGET_DIR}" \
  "${PACKER_TEMPLATE}"; then
  echo "[ERROR] Packer build failed"
  [ -f /tmp/packer-debug.log ] && tail -100 /tmp/packer-debug.log
  exit 1
fi

# NAMING CONVENTION: filter uses updated nmfs-windows-2022-oracle-client family
LATEST_IMAGE=$(gcloud compute images list \
  --project="${PROJECT_ID}" \
  --filter="family=${IMAGE_FAMILY}" \
  --sort-by="~creationTimestamp" \
  --format="value(name)" \
  --limit=1)

if [ -n "${LATEST_IMAGE}" ]; then
  OLD_IMAGES=$(gcloud compute images list \
    --project="${PROJECT_ID}" \
    # Only deprecates oracle-client images — never touches Phase 1 base images
    --filter="family=${IMAGE_FAMILY} AND name~'^nmfs-windows-2022-oracle-client' AND name!=${LATEST_IMAGE}" \
    --format="value(name)")

  while IFS= read -r IMAGE; do
    [ -z "$IMAGE" ] && continue
    gcloud compute images deprecate "${IMAGE}" \
      --project="${PROJECT_ID}" \
      --state=DEPRECATED \
      --replacement="${LATEST_IMAGE}"
  done <<< "${OLD_IMAGES}"
fi
echo "Phase 2 build complete: ${LATEST_IMAGE}"
