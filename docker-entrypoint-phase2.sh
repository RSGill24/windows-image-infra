#!/usr/bin/env bash
# ============================================================
# docker-entrypoint-phase2.sh
# Phase 2: Database Customization Entrypoint
# Runs inside the Cloud Run Job container.
# Sources Phase 1 hardened image and adds database layer.
# ============================================================

set -euo pipefail

echo "========================================================"
echo " Phase 2: Windows Database Customization Builder"
echo " $(date -u)"
echo "========================================================"

# ── Required environment variables ───────────────────────────
: "${PROJECT_ID:?PROJECT_ID env var is required}"
: "${SOURCE_IMAGE_PROJECT_ID:?SOURCE_IMAGE_PROJECT_ID env var is required}"
: "${SOURCE_IMAGE_FAMILY:?SOURCE_IMAGE_FAMILY env var is required (Phase 1 image family)}"
: "${IMAGE_FAMILY:?IMAGE_FAMILY env var is required}"
: "${ZONE:?ZONE env var is required}"
: "${MACHINE_TYPE:?MACHINE_TYPE env var is required}"
: "${SERVICE_ACCOUNT_EMAIL:?SERVICE_ACCOUNT_EMAIL env var is required}"
: "${WINRM_SECRET:?WINRM_SECRET env var is required}"
: "${PACKER_TEMPLATE:?PACKER_TEMPLATE env var is required}"

# ── Optional environment variables with defaults ─────────────
INSTALLATION_TARGET_DIR="${INSTALLATION_TARGET_DIR:=C:/Users/packer_user/installation/}"
INSTALLATION_SOURCE_DIR="${INSTALLATION_SOURCE_DIR:=./scripts}"
INSTALLATION_ENTRY_SCRIPT="${INSTALLATION_ENTRY_SCRIPT:=database_orchestrator.ps1}"

echo "[INFO] Installation Target Dir: ${INSTALLATION_TARGET_DIR}"
echo "[INFO] Installation Source Dir: ${INSTALLATION_SOURCE_DIR}"
echo "[INFO] Installation Entry Script: ${INSTALLATION_ENTRY_SCRIPT}"

# ── Load database type from config.yaml ────────────────────────
CONFIG_FILE="${CONFIG_FILE:=./config.yaml}"

if [ -f "$CONFIG_FILE" ]; then
  echo "[INFO] Loading database configuration from $CONFIG_FILE..."
  
  # Parse YAML safely using grep and awk
  DATABASE_TYPE=$(grep -E "^database_type:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '\n\r')
  
  if [ -z "$DATABASE_TYPE" ]; then
    echo "[WARN] database_type not found in config.yaml, defaulting to 'none'"
    DATABASE_TYPE="none"
  fi
else
  echo "[WARN] Config file $CONFIG_FILE not found, defaulting to 'none'"
  DATABASE_TYPE="none"
fi

# Validate database type
if [[ "$DATABASE_TYPE" != "mysql" && "$DATABASE_TYPE" != "oracle" && "$DATABASE_TYPE" != "none" ]]; then
  echo "[ERROR] Invalid database_type '${DATABASE_TYPE}'. Must be 'mysql', 'oracle', or 'none'"
  exit 1
fi

# Allow override via environment variable (for advanced usage)
if [ ! -z "${OVERRIDE_DATABASE_TYPE:-}" ]; then
  echo "[INFO] Overriding database type via OVERRIDE_DATABASE_TYPE env var"
  DATABASE_TYPE="${OVERRIDE_DATABASE_TYPE}"
fi

export DATABASE_TYPE
echo "[INFO] Database Type: ${DATABASE_TYPE}"

# ── Fetch WinRM password from Secret Manager ─────────────────
echo "Fetching WinRM password from Secret Manager..."
PACKER_PW=$(gcloud secrets versions access latest \
  --project "${PROJECT_ID}" \
  --secret "${WINRM_SECRET}")
export PACKER_PW

# ── Packer logging ───────────────────────────────────────────
export PACKER_LOG=1

# ── Initialize Packer plugins ───────────────────────────────
echo "Initializing Packer plugins..."
if ! packer init "${PACKER_TEMPLATE}" 2>&1; then
  echo "[ERROR] Packer plugin initialization failed"
  exit 1
fi

# ── Validate template ────────────────────────────────────────
echo "Validating Packer template..."
if ! packer validate \
  -var "project_id=${PROJECT_ID}" \
  -var "source_image_project_id=${SOURCE_IMAGE_PROJECT_ID}" \
  -var "source_image_family=${SOURCE_IMAGE_FAMILY}" \
  -var "service_account_email=${SERVICE_ACCOUNT_EMAIL}" \
  -var "image_family=${IMAGE_FAMILY}" \
  -var "machine_type=${MACHINE_TYPE}" \
  -var "zone=${ZONE}" \
  -var "database_type=${DATABASE_TYPE}" \
  -var "installation_source_dir=${INSTALLATION_SOURCE_DIR}" \
  -var "installation_target_dir=${INSTALLATION_TARGET_DIR}" \
  -var "installation_entry_script=${INSTALLATION_ENTRY_SCRIPT}" \
  "${PACKER_TEMPLATE}" 2>&1; then
  echo "[ERROR] Packer template validation failed"
  exit 1
fi

# ── Run Packer build ─────────────────────────────────────────
echo "Starting Packer build with database customization..."
if ! packer build \
  -var "project_id=${PROJECT_ID}" \
  -var "source_image_project_id=${SOURCE_IMAGE_PROJECT_ID}" \
  -var "source_image_family=${SOURCE_IMAGE_FAMILY}" \
  -var "service_account_email=${SERVICE_ACCOUNT_EMAIL}" \
  -var "image_family=${IMAGE_FAMILY}" \
  -var "machine_type=${MACHINE_TYPE}" \
  -var "zone=${ZONE}" \
  -var "database_type=${DATABASE_TYPE}" \
  -var "installation_source_dir=${INSTALLATION_SOURCE_DIR}" \
  -var "installation_target_dir=${INSTALLATION_TARGET_DIR}" \
  -var "installation_entry_script=${INSTALLATION_ENTRY_SCRIPT}" \
  "${PACKER_TEMPLATE}" 2>&1; then
  echo "[ERROR] Packer build failed"
  exit 1
fi

echo "Packer build completed successfully."

# ── Deprecate older images ───────────────────────────────────
echo "Deprecating older images in family ${IMAGE_FAMILY}..."

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
echo " Phase 2 Build Complete!"
echo "========================================================"
