#!/usr/bin/env bash
# ============================================================
# setup-cloudrun-job.sh
# Helper script to configure Cloud Run Job with all required
# environment variables for Phase 2 database customization
# ============================================================

set -euo pipefail

echo "========================================================"
echo " Phase 2: Cloud Run Job Configuration Helper"
echo "========================================================"

# ── Get configuration from command line or defaults ─────────
PROJECT_ID="${1:-big-mender-473219-r2}"
REGION="${2:-us-east4}"
JOB_NAME="${3:-database-image-build}"
DATABASE_TYPE="${4:-mysql}"

# ── Derived values ──────────────────────────────────────────
SOURCE_IMAGE_PROJECT_ID="${PROJECT_ID}"
SOURCE_IMAGE_FAMILY="pww-disa--hardened-patched-1777652372"
IMAGE_FAMILY="pww-windows-2022-db"
ZONE="${REGION}-b"
MACHINE_TYPE="e2-standard-8"
SERVICE_ACCOUNT="packer-win-sa@${PROJECT_ID}.iam.gserviceaccount.com"
WINRM_SECRET="packer-winrm-password"
DOCKER_IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/packer-images/windows-packer-db-customizer:latest"
PACKER_TEMPLATE="customize_db.pkr.hcl"

# ── Optional variables (with sensible defaults) ──────────────
INSTALLATION_TARGET_DIR="C:/Users/packer_user/installation/"
INSTALLATION_SOURCE_DIR="./scripts"
INSTALLATION_ENTRY_SCRIPT="database_orchestrator.ps1"

echo ""
echo "Configuration Summary:"
echo "─────────────────────────────────────────────────────"
echo "  Project ID:               ${PROJECT_ID}"
echo "  Region:                   ${REGION}"
echo "  Job Name:                 ${JOB_NAME}"
echo "  Docker Image:             ${DOCKER_IMAGE}"
echo "  Database Type:            ${DATABASE_TYPE}"
echo "  Source Image Family:      ${SOURCE_IMAGE_FAMILY}"
echo "  Target Image Family:      ${IMAGE_FAMILY}"
echo "  Zone:                     ${ZONE}"
echo "  Machine Type:             ${MACHINE_TYPE}"
echo "  Service Account:          ${SERVICE_ACCOUNT}"
echo "  Installation Target:      ${INSTALLATION_TARGET_DIR}"
echo "─────────────────────────────────────────────────────"

# ── Check if job exists ─────────────────────────────────────
JOB_EXISTS=$(gcloud run jobs describe "${JOB_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  2>/dev/null || echo "")

if [ -z "${JOB_EXISTS}" ]; then
  echo ""
  echo "Creating Cloud Run Job: ${JOB_NAME}..."
  gcloud beta run jobs create "${JOB_NAME}" \
    --image="${DOCKER_IMAGE}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}" \
    --cpu=8 \
    --memory=32Gi \
    --timeout=7200s \
    --service-account="${SERVICE_ACCOUNT}" \
    --set-env-vars \
    PROJECT_ID="${PROJECT_ID}",\
    SOURCE_IMAGE_PROJECT_ID="${SOURCE_IMAGE_PROJECT_ID}",\
    SOURCE_IMAGE_FAMILY="${SOURCE_IMAGE_FAMILY}",\
    IMAGE_FAMILY="${IMAGE_FAMILY}",\
    ZONE="${ZONE}",\
    MACHINE_TYPE="${MACHINE_TYPE}",\
    SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT}",\
    WINRM_SECRET="${WINRM_SECRET}",\
    INSTALLATION_TARGET_DIR="${INSTALLATION_TARGET_DIR}",\
    INSTALLATION_SOURCE_DIR="${INSTALLATION_SOURCE_DIR}",\
    INSTALLATION_ENTRY_SCRIPT="${INSTALLATION_ENTRY_SCRIPT}",\
    PACKER_TEMPLATE="${PACKER_TEMPLATE}",\
    DATABASE_TYPE="${DATABASE_TYPE}"
  
  echo "✅ Job created successfully!"
else
  echo ""
  echo "Updating existing Cloud Run Job: ${JOB_NAME}..."
  gcloud beta run jobs update "${JOB_NAME}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}" \
    --image="${DOCKER_IMAGE}" \
    --set-env-vars \
    PROJECT_ID="${PROJECT_ID}",\
    SOURCE_IMAGE_PROJECT_ID="${SOURCE_IMAGE_PROJECT_ID}",\
    SOURCE_IMAGE_FAMILY="${SOURCE_IMAGE_FAMILY}",\
    IMAGE_FAMILY="${IMAGE_FAMILY}",\
    ZONE="${ZONE}",\
    MACHINE_TYPE="${MACHINE_TYPE}",\
    SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT}",\
    WINRM_SECRET="${WINRM_SECRET}",\
    INSTALLATION_TARGET_DIR="${INSTALLATION_TARGET_DIR}",\
    INSTALLATION_SOURCE_DIR="${INSTALLATION_SOURCE_DIR}",\
    INSTALLATION_ENTRY_SCRIPT="${INSTALLATION_ENTRY_SCRIPT}",\
    PACKER_TEMPLATE="${PACKER_TEMPLATE}",\
    DATABASE_TYPE="${DATABASE_TYPE}"
  
  echo "✅ Job updated successfully!"
fi

echo ""
echo "========================================================"
echo " Next Steps"
echo "========================================================"
echo ""
echo "Execute the job with:"
echo "  gcloud run jobs execute ${JOB_NAME} --region=${REGION}"
echo ""
echo "Monitor logs with:"
echo "  gcloud logging read \"resource.type=cloud_run_job AND resource.labels.job_name=${JOB_NAME}\" --limit=100 --format=json"
echo ""
