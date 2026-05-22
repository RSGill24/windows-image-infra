#!/usr/bin/env bash
# ============================================================
# docker-entrypoint.sh
# Phase 2: Oracle Client Image Builder
# Runs inside the Cloud Run Job container.
# ============================================================

set -euo pipefail

echo "========================================================"
echo " Phase 2: Oracle Client Image Builder"
echo " $(date -u)"
echo "========================================================"

# ── Required environment variables ───────────────────────────
# These are injected by the Cloud Run Job definition
: "${PROJECT_ID:?PROJECT_ID env var is required}"
: "${SOURCE_IMAGE_PROJECT_ID:?SOURCE_IMAGE_PROJECT_ID env var is required}"
: "${SOURCE_IMAGE_FAMILY:?SOURCE_IMAGE_FAMILY env var is required}"
: "${IMAGE_FAMILY:?IMAGE_FAMILY env var is required}"
: "${ZONE:?ZONE env var is required}"
: "${MACHINE_TYPE:?MACHINE_TYPE env var is required}"
: "${SERVICE_ACCOUNT_EMAIL:?SERVICE_ACCOUNT_EMAIL env var is required}"
: "${WINRM_SECRET:?WINRM_SECRET env var is required}"
: "${INSTALLATION_SOURCE_DIR:?INSTALLATION_SOURCE_DIR env var is required}"
: "${INSTALLATION_TARGET_DIR:?INSTALLATION_TARGET_DIR env var is required}"
: "${PACKER_TEMPLATE:?PACKER_TEMPLATE env var is required}"

# ── Packer logging ───────────────────────────────────────────
export PACKER_LOG=1
export PACKER_LOG_PATH="/tmp/packer-debug.log"

# ── Validate template exists ─────────────────────────────────
if [ ! -f "${PACKER_TEMPLATE}" ]; then
  echo "[ERROR] Packer template not found: ${PACKER_TEMPLATE}"
  exit 1
fi

# ── Fetch WinRM password from Secret Manager ─────────────────
echo "Fetching WinRM password from Secret Manager..."
PACKER_PW=$(gcloud secrets versions access latest \
  --project "${PROJECT_ID}" \
  --secret "${WINRM_SECRET}")
export PACKER_PW

# ── Check gcloud auth ────────────────────────────────────────
if ! gcloud auth list 2>&1 | grep -q "ACTIVE"; then
  echo "[ERROR] gcloud is not authenticated"
  exit 1
fi

# ── Init & Validate Packer template ──────────────────────────
echo "Initialising Packer plugins..."
packer init "${PACKER_TEMPLATE}"

echo "Validating Packer template..."
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

# ── Run Packer build ─────────────────────────────────────────
echo "Starting Packer build..."
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

echo "Packer build completed successfully."

# ── Deprecate older oracle-client images only ────────────────

# ── Deprecate older oracle-client images only ────────────────
echo "Deprecating older images in family ${IMAGE_FAMILY}..."

LATEST_IMAGE=$(gcloud compute images list \
  --project="${PROJECT_ID}" \
  --no-standard-images \
  --sort-by="~creationTimestamp" \
  --format="value(name)" \
  --filter="family=${IMAGE_FAMILY}" \
  --limit=1)

echo "Latest image: ${LATEST_IMAGE}"

if [ -n "${LATEST_IMAGE}" ]; then
  # Get all images in family, skip latest, skip Phase 1 base images in bash
  OLD_IMAGES=$(gcloud compute images list \
    --project="${PROJECT_ID}" \
    --no-standard-images \
    --sort-by="~creationTimestamp" \
    --format="value(name)" \
    --filter="family=${IMAGE_FAMILY}" \
    | grep "oracle-client" \
    | grep -v "${LATEST_IMAGE}" || true)

  while IFS= read -r IMAGE; do
    [ -z "$IMAGE" ] && continue
    echo "Deprecating: ${IMAGE}"
    gcloud compute images deprecate "${IMAGE}" \
      --project="${PROJECT_ID}" \
      --state=DEPRECATED \
      --replacement="${LATEST_IMAGE}"
  done <<< "${OLD_IMAGES}"
fi

echo "Phase 2 build complete: ${LATEST_IMAGE}"
