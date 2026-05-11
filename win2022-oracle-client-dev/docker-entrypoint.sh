#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# docker-entrypoint.sh
#
# Parameterized entrypoint for the Windows image builder container.
#
# Installation flags (set via Cloud Run env vars / Terraform):
#   INSTALL_ORACLE    – "true"/"false"  (default: false)
#   INSTALL_RSTUDIO   – "true"/"false"  (default: false)
#   INSTALL_CONDA     – "true"/"false"  (default: false)
#
# Image / infra vars (set via Cloud Run env vars / Terraform):
#   PROJECT_ID, SOURCE_IMAGE_PROJECT_ID, SOURCE_IMAGE_FAMILY
#   IMAGE_FAMILY, ZONE, MACHINE_TYPE, SERVICE_ACCOUNT_EMAIL
#   WINRM_SECRET, INSTALLATION_TARGET_DIR, INSTALLATION_SOURCE_DIR
#   PACKER_TEMPLATE
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

echo "Phase 2: Parameterized Windows Image Builder — $(date -u)"
packer version

# ── Resolve infra variables (env vars passed from Cloud Run) ──────────────────
PROJECT_ID="${PROJECT_ID:?ERROR: PROJECT_ID env var is required}"
SOURCE_IMAGE_PROJECT_ID="${SOURCE_IMAGE_PROJECT_ID:-${PROJECT_ID}}"
SOURCE_IMAGE_FAMILY="${SOURCE_IMAGE_FAMILY:?ERROR: SOURCE_IMAGE_FAMILY env var is required}"
IMAGE_FAMILY="${IMAGE_FAMILY:?ERROR: IMAGE_FAMILY env var is required}"
ZONE="${ZONE:?ERROR: ZONE env var is required}"
MACHINE_TYPE="${MACHINE_TYPE:-e2-standard-8}"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_EMAIL:?ERROR: SERVICE_ACCOUNT_EMAIL env var is required}"
WINRM_SECRET="${WINRM_SECRET:-packer-winrm-password}"

INSTALLATION_TARGET_DIR="${INSTALLATION_TARGET_DIR:-C:/Users/packer_user/installation/}"
INSTALLATION_SOURCE_DIR="${INSTALLATION_SOURCE_DIR:-./ansible-playbook}"
PACKER_TEMPLATE="${PACKER_TEMPLATE:-customize.pkr.hcl}"

# ── Resolve installation component flags ─────────────────────────────────────
# Accepts "true" / "True" / "1" / "yes" as truthy (case-insensitive)
to_bool() {
  local val
  val=$(echo "${1:-false}" | tr '[:upper:]' '[:lower:]')
  case "$val" in
    true|1|yes) echo "true" ;;
    *)           echo "false" ;;
  esac
}

INSTALL_ORACLE=$(to_bool "${INSTALL_ORACLE:-false}")
INSTALL_RSTUDIO=$(to_bool "${INSTALL_RSTUDIO:-false}")
INSTALL_CONDA=$(to_bool "${INSTALL_CONDA:-false}")

echo "──────────────────────────────────────────────"
echo "  Installation components:"
echo "    Oracle Client : ${INSTALL_ORACLE}"
echo "    RStudio       : ${INSTALL_RSTUDIO}"
echo "    Conda/Python  : ${INSTALL_CONDA}"
echo "  Infra:"
echo "    PROJECT_ID    : ${PROJECT_ID}"
echo "    IMAGE_FAMILY  : ${IMAGE_FAMILY}"
echo "    ZONE          : ${ZONE}"
echo "──────────────────────────────────────────────"

# Guard: at least one component must be selected
if [ "${INSTALL_ORACLE}" = "false" ] && \
   [ "${INSTALL_RSTUDIO}" = "false" ] && \
   [ "${INSTALL_CONDA}" = "false" ]; then
  echo "[WARN] No components selected (INSTALL_ORACLE / INSTALL_RSTUDIO / INSTALL_CONDA are all false)."
  echo "[WARN] Nothing to install – exiting early."
  exit 0
fi

# ── Fetch WinRM secret ────────────────────────────────────────────────────────
PACKER_PW=$(gcloud secrets versions access latest \
  --project "${PROJECT_ID}" \
  --secret "${WINRM_SECRET}")
export PACKER_PW

# ── Packer debug logging ──────────────────────────────────────────────────────
export PACKER_LOG=1
export PACKER_LOG_PATH="/tmp/packer-debug.log"

# ── Sanity-check template ─────────────────────────────────────────────────────
if [ ! -f "${PACKER_TEMPLATE}" ]; then
  echo "[ERROR] Packer template not found: ${PACKER_TEMPLATE}"
  exit 1
fi

# ── Build the ansible extra-vars string ──────────────────────────────────────
# These are forwarded into customize.pkr.hcl → shell-local → ansible-playbook
ANSIBLE_EXTRA_VARS="install_oracle=${INSTALL_ORACLE} install_rstudio=${INSTALL_RSTUDIO} install_conda=${INSTALL_CONDA}"
export ANSIBLE_EXTRA_VARS

# ── Packer init ───────────────────────────────────────────────────────────────
packer init "${PACKER_TEMPLATE}"

# ── Common packer -var flags ──────────────────────────────────────────────────
PACKER_VARS=(
  -var "project_id=${PROJECT_ID}"
  -var "source_image_project_id=${SOURCE_IMAGE_PROJECT_ID}"
  -var "source_image_family=${SOURCE_IMAGE_FAMILY}"
  -var "service_account_email=${SERVICE_ACCOUNT_EMAIL}"
  -var "image_family=${IMAGE_FAMILY}"
  -var "machine_type=${MACHINE_TYPE}"
  -var "zone=${ZONE}"
  -var "installation_source_dir=${INSTALLATION_SOURCE_DIR}"
  -var "installation_target_dir=${INSTALLATION_TARGET_DIR}"
  -var "install_oracle=${INSTALL_ORACLE}"
  -var "install_rstudio=${INSTALL_RSTUDIO}"
  -var "install_conda=${INSTALL_CONDA}"
)

# ── Validate ──────────────────────────────────────────────────────────────────
packer validate "${PACKER_VARS[@]}" "${PACKER_TEMPLATE}"

# ── gcloud auth check ─────────────────────────────────────────────────────────
if ! gcloud auth list 2>&1 | grep -q "ACTIVE"; then
  echo "[ERROR] gcloud is not authenticated"
  exit 1
fi

# ── Packer build ──────────────────────────────────────────────────────────────
if ! packer build "${PACKER_VARS[@]}" "${PACKER_TEMPLATE}"; then
  echo "[ERROR] Packer build failed"
  [ -f /tmp/packer-debug.log ] && tail -100 /tmp/packer-debug.log
  exit 1
fi

# ── Deprecate old images ──────────────────────────────────────────────────────
LATEST_IMAGE=$(gcloud compute images list \
  --project="${PROJECT_ID}" \
  --filter="family=${IMAGE_FAMILY}" \
  --sort-by="~creationTimestamp" \
  --format="value(name)" \
  --limit=1)

if [ -n "${LATEST_IMAGE}" ]; then
  OLD_IMAGES=$(gcloud compute images list \
    --project="${PROJECT_ID}" \
    --filter="family=${IMAGE_FAMILY} AND name!=${LATEST_IMAGE}" \
    --format="value(name)")

  while IFS= read -r IMAGE; do
    [ -z "$IMAGE" ] && continue
    gcloud compute images deprecate "${IMAGE}" \
      --project="${PROJECT_ID}" \
      --state=DEPRECATED \
      --replacement="${LATEST_IMAGE}"
  done <<< "${OLD_IMAGES}"
fi

echo "Build complete: ${LATEST_IMAGE}"
echo "Components installed — oracle:${INSTALL_ORACLE}  rstudio:${INSTALL_RSTUDIO}  conda:${INSTALL_CONDA}"
