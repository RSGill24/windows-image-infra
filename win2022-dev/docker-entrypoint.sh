#!/usr/bin/env bash
# ============================================================
# docker-entrypoint.sh
# Runs inside the Cloud Run Job container.
# Uses injected secrets and executes the Packer build.
#
# FIXES:
#   - Verifies VPC/IAP connectivity before running Packer
#   - Structured logging for Cloud Logging
#   - PACKER_LOG_PATH for full debug output
#   - Explicit gcloud auth via workload identity
#   - Plugin cache dir set explicitly
# ============================================================

set -euo pipefail

echo "========================================================"
echo " Windows STIG Hardened Image Builder"
echo " $(date -u)"
echo "========================================================"

# ── Required environment variables ───────────────────────────
: "${PROJECT_ID:?PROJECT_ID env var is required}"
: "${SOURCE_IMAGE_PROJECT_ID:?SOURCE_IMAGE_PROJECT_ID env var is required}"
: "${SOURCE_IMAGE_FAMILY:?SOURCE_IMAGE_FAMILY env var is required}"
: "${IMAGE_FAMILY:?IMAGE_FAMILY env var is required}"
: "${ZONE:?ZONE env var is required}"
: "${MACHINE_TYPE:?MACHINE_TYPE env var is required}"
: "${SERVICE_ACCOUNT_EMAIL:?SERVICE_ACCOUNT_EMAIL env var is required}"
: "${WINRM_SECRET:?WINRM_SECRET env var is required}"
: "${HARDENING_TARGET_DIR:?HARDENING_TARGET_DIR env var is required}"
: "${PACKER_TEMPLATE:?PACKER_TEMPLATE env var is required}"

# ── Packer logging ───────────────────────────────────────────
export PACKER_LOG=1
export PACKER_LOG_PATH="/tmp/packer_debug.log"

# ── Plugin cache — use persistent dir so init is not re-run ──
export PACKER_PLUGIN_PATH="/workspace/.packer.d/plugins"

# ── Use WinRM password injected by Cloud Run ─────────────────
echo "Using WinRM password injected by Cloud Run..."
export PACKER_PW="${WINRM_SECRET}"
export SRC_IMG_NAME="${SOURCE_IMAGE_FAMILY}"

# ── Step 1: Verify gcloud auth (Workload Identity in Cloud Run)
echo ">>> [1] Verifying gcloud authentication..."
gcloud auth list --filter=status:ACTIVE --format="value(account)" || {
    echo "ERROR: gcloud auth failed — check Workload Identity binding on Cloud Run Job"
    exit 1
}
gcloud config set project "${PROJECT_ID}"
echo "Auth OK."

# ── Step 2: Verify IAP API is enabled ────────────────────────
echo ">>> [2] Verifying IAP tunnel connectivity to GCP..."
curl -s -o /dev/null -w "%{http_code}" \
    "https://iap.googleapis.com/" | grep -q "200\|404" && \
    echo "IAP endpoint reachable." || \
    echo "WARNING: IAP endpoint may not be reachable — check VPC connector egress"

# ── Step 3: Verify network connectivity to internal subnet ───
echo ">>> [3] Checking VPC egress configuration..."
VPC_SUBNET_REACHABLE=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 5 \
    "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/subnetwork" \
    -H "Metadata-Flavor: Google" || echo "000")

if [ "$VPC_SUBNET_REACHABLE" != "000" ]; then
    echo "Running inside GCP — metadata server reachable."
else
    echo "WARNING: Metadata server not reachable."
fi

# ── Step 4: Re-init Packer plugins if needed ─────────────────
echo ">>> [4] Initializing Packer plugins..."
packer init "${PACKER_TEMPLATE}"
echo "Packer plugins ready."

# ── Step 5: Validate Packer template ─────────────────────────
echo ">>> [5] Validating Packer template..."
packer validate \
  -var "project_id=${PROJECT_ID}" \
  -var "source_image_project_id=${SOURCE_IMAGE_PROJECT_ID}" \
  -var "source_image_family=${SOURCE_IMAGE_FAMILY}" \
  -var "service_account_email=${SERVICE_ACCOUNT_EMAIL}" \
  -var "image_family=${IMAGE_FAMILY}" \
  -var "machine_type=${MACHINE_TYPE}" \
  -var "zone=${ZONE}" \
  -var "hardening_source_dir=./scripts" \
  -var "hardening_target_dir=${HARDENING_TARGET_DIR}" \
  -var "hardening_entry_script=run_all.ps1" \
  "${PACKER_TEMPLATE}"
echo "Template valid."

# ── Step 6: Run Packer build ──────────────────────────────────
echo ">>> [6] Starting Packer build..."
packer build \
  -on-error=abort \
  -var "project_id=${PROJECT_ID}" \
  -var "source_image_project_id=${SOURCE_IMAGE_PROJECT_ID}" \
  -var "source_image_family=${SOURCE_IMAGE_FAMILY}" \
  -var "service_account_email=${SERVICE_ACCOUNT_EMAIL}" \
  -var "image_family=${IMAGE_FAMILY}" \
  -var "machine_type=${MACHINE_TYPE}" \
  -var "zone=${ZONE}" \
  -var "hardening_source_dir=./scripts" \
  -var "hardening_target_dir=${HARDENING_TARGET_DIR}" \
  -var "hardening_entry_script=run_all.ps1" \
  "${PACKER_TEMPLATE}"

BUILD_EXIT=$?

# ── Step 7: Upload Packer debug log to Cloud Logging ─────────
if [ -f "${PACKER_LOG_PATH}" ]; then
    echo ">>> Packer debug log (last 100 lines):"
    tail -100 "${PACKER_LOG_PATH}"
fi

if [ $BUILD_EXIT -ne 0 ]; then
    echo "ERROR: Packer build failed with exit code $BUILD_EXIT"
    exit $BUILD_EXIT
fi

echo "Packer build completed successfully."

# ── Step 8: Deprecate older images ───────────────────────────
echo ">>> [7] Deprecating older images in family ${IMAGE_FAMILY}..."

LATEST_IMAGE=$(gcloud compute images list \
  --project="${PROJECT_ID}" \
  --filter="family=${IMAGE_FAMILY}" \
  --sort-by="~creationTimestamp" \
  --format="value(name)" \
  --limit=1)

echo "Latest image: ${LATEST_IMAGE}"

OLD_IMAGES=$(gcloud compute images list \
  --project="${PROJECT_ID}" \
  --filter="family=${IMAGE_FAMILY} AND name!=${LATEST_IMAGE}" \
  --format="value(name)")

if [ -z "${OLD_IMAGES}" ]; then
    echo "No older images to deprecate."
else
    for IMAGE in ${OLD_IMAGES}; do
        echo "Deprecating: ${IMAGE}"
        gcloud compute images deprecate "${IMAGE}" \
          --project="${PROJECT_ID}" \
          --state=DEPRECATED \
          --replacement="${LATEST_IMAGE}"
    done
    echo "Old images deprecated successfully."
fi

echo "========================================================"
echo " Build complete: ${LATEST_IMAGE}"
echo " $(date -u)"
echo "========================================================"