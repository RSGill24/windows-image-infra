#!/usr/bin/env bash
# ============================================================
# docker-entrypoint-phase2.sh
# Phase 2: Database Customization Entrypoint
# Runs inside the Cloud Run Job container.
# Sources Phase 1 hardened image and adds database layer.
# ============================================================

set -euo pipefail

echo "========================================================"
echo " Phase 2: Windows client Customization Builder"
echo " $(date -u)"
echo "========================================================"
echo "[INFO] Working directory: $(pwd)"
echo "[INFO] Packer version:"
packer version 2>&1 || echo "[WARN] Could not get packer version"
echo ""
echo "[INFO] Script PID: $$, PPID: $PPID"
echo "[INFO] Shell: $SHELL, Bash Version: ${BASH_VERSION}"

# ── Hardcoded configuration values ───────────────────────────
PROJECT_ID="big-mender-473219-r2"
SOURCE_IMAGE_PROJECT_ID="big-mender-473219-r2"
SOURCE_IMAGE_FAMILY="pww-windows-2022-hardened"
IMAGE_FAMILY="pww-windows-2022-db"
ZONE="us-east4-b"
MACHINE_TYPE="e2-standard-8"
SERVICE_ACCOUNT_EMAIL="packer-win-sa@big-mender-473219-r2.iam.gserviceaccount.com"
WINRM_SECRET="packer-winrm-password"

# ── Optional environment variables with defaults ─────────────
INSTALLATION_TARGET_DIR="C:/Users/packer_user/installation/"
INSTALLATION_SOURCE_DIR="./scripts"
INSTALLATION_ENTRY_SCRIPT="oracle.ps1"

# ── CRITICAL: Phase 2 uses customize_db.pkr.hcl ONLY ────────
PACKER_TEMPLATE="customize_db.pkr.hcl"

echo "[INFO] Installation Target Dir: ${INSTALLATION_TARGET_DIR}"
echo "[INFO] Installation Source Dir: ${INSTALLATION_SOURCE_DIR}"
echo "[INFO] Installation Entry Script: ${INSTALLATION_ENTRY_SCRIPT}"

# ── Load database type from config.yaml ──────────────────────
CONFIG_FILE="./config.yaml"

if [ -f "$CONFIG_FILE" ]; then
  echo "[INFO] Loading oracle client from $CONFIG_FILE..."
  DATABASE_TYPE=$(grep -E "^oracle_file:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '\n\r')
  if [ -z "$DATABASE_TYPE" ]; then
    echo "[WARN] oracle_client not found in config.yaml, defaulting to 'none'"
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

# Allow override via environment variable
if [ -n "${OVERRIDE_DATABASE_TYPE:-}" ]; then
  echo "[INFO] Overriding database type via OVERRIDE_DATABASE_TYPE env var"
  DATABASE_TYPE="${OVERRIDE_DATABASE_TYPE}"
fi

export DATABASE_TYPE
echo "[INFO] Database Type: ${DATABASE_TYPE}"

# ── Display configuration summary ────────────────────────────
echo ""
echo "Configuration Summary:"
echo "─────────────────────────────────────────────────────"
echo "  PROJECT_ID:              ${PROJECT_ID}"
echo "  SOURCE_IMAGE_PROJECT_ID: ${SOURCE_IMAGE_PROJECT_ID}"
echo "  SOURCE_IMAGE_FAMILY:     ${SOURCE_IMAGE_FAMILY}"
echo "  IMAGE_FAMILY:            ${IMAGE_FAMILY}"
echo "  ZONE:                    ${ZONE}"
echo "  MACHINE_TYPE:            ${MACHINE_TYPE}"
echo "  SERVICE_ACCOUNT_EMAIL:   ${SERVICE_ACCOUNT_EMAIL}"
echo "  DATABASE_TYPE:           ${DATABASE_TYPE}"
echo "  PACKER_TEMPLATE:         ${PACKER_TEMPLATE}"
echo "─────────────────────────────────────────────────────"
echo ""

# ── Fetch WinRM password from Secret Manager ─────────────────
echo "Fetching WinRM password from Secret Manager..."
PACKER_PW=$(gcloud secrets versions access latest \
  --project "${PROJECT_ID}" \
  --secret "${WINRM_SECRET}")
export PACKER_PW

# ── Packer logging ───────────────────────────────────────────
export PACKER_LOG=1
export PACKER_LOG_PATH="/tmp/packer-debug.log"

# ── Verify Packer template exists ────────────────────────────
if [ ! -f "${PACKER_TEMPLATE}" ]; then
  echo "[ERROR] Packer template not found: ${PACKER_TEMPLATE}"
  echo "[ERROR] Phase 2 requires: customize_db.pkr.hcl"
  echo ""
  echo "[DEBUG] Current working directory: $(pwd)"
  echo "[DEBUG] Files in current directory:"
  ls -lah
  echo ""
  echo "[DEBUG] Looking for .pkr.hcl files:"
  find . -maxdepth 1 -name "*.pkr.hcl" -type f || echo "No .pkr.hcl files found"
  echo ""
  echo "[ERROR] SOLUTION: Ensure Dockerfile has: COPY customize_db.pkr.hcl ./customize_db.pkr.hcl"
  exit 1
fi

echo "[INFO] Packer template: ${PACKER_TEMPLATE} ✓"
echo "[INFO] Working directory: $(pwd)"
echo "[INFO] Template absolute path: $(cd "$(dirname "${PACKER_TEMPLATE}")" && pwd)/$(basename "${PACKER_TEMPLATE}")"

# ── Initialize Packer plugins ────────────────────────────────
echo "Initializing Packer plugins..."
if OUTPUT=$(packer init "${PACKER_TEMPLATE}" 2>&1); then
  echo "[INFO] Packer plugins initialized successfully"
  echo "$OUTPUT"
else
  INIT_EXIT_CODE=$?
  echo "[ERROR] Packer plugin initialization failed (exit code: ${INIT_EXIT_CODE})"
  echo "$OUTPUT"
  if [ -f "/tmp/packer-debug.log" ]; then
    cat "/tmp/packer-debug.log"
  fi
  exit 1
fi

# ── Validate template ─────────────────────────────────────────
echo "Validating Packer template..."
if VALIDATION_OUTPUT=$(packer validate \
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
  "${PACKER_TEMPLATE}" 2>&1); then
  echo "[INFO] Packer template validation successful"
  echo "$VALIDATION_OUTPUT"
else
  VALIDATE_EXIT_CODE=$?
  echo "[ERROR] Packer template validation failed (exit code: ${VALIDATE_EXIT_CODE})"
  echo "$VALIDATION_OUTPUT"
  if [ -f "/tmp/packer-debug.log" ]; then
    tail -50 "/tmp/packer-debug.log"
  fi
  exit 1
fi

# ── Check gcloud authentication ───────────────────────────────
echo "Checking gcloud authentication..."
if ! gcloud auth list 2>&1 | grep -q "ACTIVE"; then
  echo "[ERROR] gcloud is not authenticated. Cannot proceed with build."
  gcloud auth list || true
  exit 1
fi
echo "[INFO] gcloud authentication verified"

# ── Run Packer build ──────────────────────────────────────────
echo "Starting Packer build with oracle customization..."
if packer build \
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
  echo "========================================================"
  echo " Packer build completed successfully."
  echo "========================================================"
else
  BUILD_EXIT_CODE=$?
  echo "[ERROR] Packer build failed (exit code: ${BUILD_EXIT_CODE})"
  if [ -f "/tmp/packer-debug.log" ]; then
    tail -100 "/tmp/packer-debug.log"
  fi
  exit 1
fi

# ── Deprecate older images ────────────────────────────────────
echo "Deprecating older images in family ${IMAGE_FAMILY}..."

LATEST_IMAGE=$(gcloud compute images list \
  --project="${PROJECT_ID}" \
  --filter="family=${IMAGE_FAMILY}" \
  --sort-by="~creationTimestamp" \
  --format="value(name)" \
  --limit=1)

if [ -z "${LATEST_IMAGE}" ]; then
  echo "[WARN] Could not find latest image, skipping deprecation."
else
  echo "Latest image: ${LATEST_IMAGE}"

  OLD_IMAGES=$(gcloud compute images list \
    --project="${PROJECT_ID}" \
    --filter="family=${IMAGE_FAMILY} AND name!=${LATEST_IMAGE}" \
    --format="value(name)")

  if [ -z "${OLD_IMAGES}" ]; then
    echo "No older images to deprecate."
  else
    while IFS= read -r IMAGE; do
      [ -z "$IMAGE" ] && continue
      echo "Deprecating: ${IMAGE}"
      gcloud compute images deprecate "${IMAGE}" \
        --project="${PROJECT_ID}" \
        --state=DEPRECATED \
        --replacement="${LATEST_IMAGE}"
    done <<< "${OLD_IMAGES}"
    echo "Old images deprecated successfully."
  fi
fi

echo "========================================================"
echo " Phase 2 Build Complete!"
echo "========================================================"
