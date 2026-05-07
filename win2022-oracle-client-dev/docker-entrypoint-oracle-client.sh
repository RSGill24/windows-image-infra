#!/usr/bin/env bash
set -euo pipefail

echo "========================================================"
echo " Phase 2: Windows Database Customization Builder"
echo " $(date -u)"
echo "========================================================"
echo "[INFO] Working directory: $(pwd)"
echo "[INFO] Packer version:"
packer version 2>&1 || echo "[WARN] Could not get packer version"
echo ""
echo "[INFO] Script PID: $$, PPID: $PPID"
echo "[INFO] Shell: $SHELL, Bash Version: ${BASH_VERSION}"

PROJECT_ID="big-mender-473219-r2"
SOURCE_IMAGE_PROJECT_ID="big-mender-473219-r2"
SOURCE_IMAGE_FAMILY="pww-windows-2022-hardened"
IMAGE_FAMILY="pww-windows-2022-oracle-client-dev"
ZONE="us-east4-b"
MACHINE_TYPE="e2-standard-8"
SERVICE_ACCOUNT_EMAIL="packer-win-sa@big-mender-473219-r2.iam.gserviceaccount.com"
WINRM_SECRET="packer-winrm-password"

INSTALLATION_TARGET_DIR="C:/Users/packer_user/installation/"
INSTALLATION_SOURCE_DIR="./ansible-playbook"  # Directory containing database installation playbooks
INSTALLATION_ENTRY_SCRIPT=""  # Not used - database setup handled by Ansible playbook

PACKER_TEMPLATE="customize_db.pkr.hcl"

echo "[INFO] Installation Target Dir: ${INSTALLATION_TARGET_DIR}"
echo "[INFO] Installation Source Dir: ${INSTALLATION_SOURCE_DIR}"
echo "[INFO] Installation Entry Script: ${INSTALLATION_ENTRY_SCRIPT}"

CONFIG_FILE="./config.yaml"

if [ -f "$CONFIG_FILE" ]; then
  echo "[INFO] Loading database configuration from $CONFIG_FILE..."
  DATABASE_TYPE=$(grep -E "^database_type:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '\n\r')
  if [ -z "$DATABASE_TYPE" ]; then
    echo "[WARN] database_type not found in config.yaml, defaulting to 'none'"
    DATABASE_TYPE="none"
  fi
else
  echo "[WARN] Config file $CONFIG_FILE not found, defaulting to 'none'"
  DATABASE_TYPE="none"
fi

if [[ "$DATABASE_TYPE" != "mysql" && "$DATABASE_TYPE" != "oracle" && "$DATABASE_TYPE" != "none" ]]; then
  echo "[ERROR] Invalid database_type '${DATABASE_TYPE}'. Must be 'mysql', 'oracle', or 'none'"
  exit 1
fi

if [ -n "${OVERRIDE_DATABASE_TYPE:-}" ]; then
  echo "[INFO] Overriding database type via OVERRIDE_DATABASE_TYPE env var"
  DATABASE_TYPE="${OVERRIDE_DATABASE_TYPE}"
fi

export DATABASE_TYPE
echo "[INFO] Database Type: ${DATABASE_TYPE}"

echo "Fetching WinRM password from Secret Manager..."
PACKER_PW=$(gcloud secrets versions access latest \
  --project "${PROJECT_ID}" \
  --secret "${WINRM_SECRET}")
export PACKER_PW

export PACKER_LOG=1
export PACKER_LOG_PATH="/tmp/packer-debug.log"

if [ ! -f "${PACKER_TEMPLATE}" ]; then
  echo "[ERROR] Packer template not found: ${PACKER_TEMPLATE}"
  echo "[ERROR] Current working directory: $(pwd)"
  exit 1
fi

echo "[INFO] Packer template: ${PACKER_TEMPLATE}"

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

echo "Checking gcloud authentication..."
if ! gcloud auth list 2>&1 | grep -q "ACTIVE"; then
  echo "[ERROR] gcloud is not authenticated. Cannot proceed with build."
  gcloud auth list || true
  exit 1
fi
echo "[INFO] gcloud authentication verified"

echo "Starting Packer build with database customization..."
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

echo "Build Complete!"
