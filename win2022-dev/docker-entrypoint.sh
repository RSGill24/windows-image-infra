#!/usr/bin/env bash
# ============================================================
# docker-entrypoint.sh
# Runs inside the Cloud Run Job container.
# Fetches secrets, validates, and executes the Packer build.
# ============================================================

set -euo pipefail

echo "========================================================"
echo " Windows STIG Hardened Image Builder"
echo " $(date -u)"
echo "========================================================"

# ── Required environment variables ───────────────────────────
# These are injected by the Cloud Run Job definition (Terraform)
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

# ── Authenticate against the Cloud Run metadata server ───────
# Cloud Run supplies credentials via the metadata server, but gcloud only uses
# them once it has an active account. Older gcloud builds auto-detected this;
# newer ones did not here, and every gcloud call failed with:
#   ERROR: (gcloud.secrets.versions.access) You do not currently have an
#          active account selected.
# Set it explicitly rather than depending on version-specific auto-detection.
# Clear any GCE-detection cache inherited from image build time. If a gcloud
# command ever runs during "docker build", it caches "False" into this directory
# and the running container will refuse to use metadata credentials.
rm -rf /root/.config/gcloud/gce "${HOME:-/root}/.config/gcloud/gce" 2>/dev/null || true

MD="http://metadata.google.internal/computeMetadata/v1"
MD_HDR="Metadata-Flavor: Google"

SA_EMAIL=$(curl -s -m 5 -H "${MD_HDR}" "${MD}/instance/service-accounts/default/email" || true)
if [ -n "${SA_EMAIL}" ]; then
  echo "Metadata service account: ${SA_EMAIL}"
  export CLOUDSDK_CORE_ACCOUNT="${SA_EMAIL}"
  gcloud config set account "${SA_EMAIL}" --quiet 2>/dev/null || true
else
  echo "WARNING: could not read service account from metadata server."
fi
echo "gcloud accounts visible:"
gcloud auth list --format='value(account,status)' 2>&1 | sed 's/^/  /' || true

# ── Fetch WinRM password from Secret Manager ─────────────────
# Try gcloud first; fall back to the Secret Manager REST API using a metadata
# token. The fallback depends only on curl, so it works regardless of how
# gcloud resolves credentials.
echo "Fetching WinRM password from Secret Manager..."
PACKER_PW=$(gcloud secrets versions access latest \
  --project "${PROJECT_ID}" \
  --secret "${WINRM_SECRET}" 2>/dev/null || true)

if [ -z "${PACKER_PW}" ]; then
  echo "gcloud path failed; falling back to Secret Manager REST API..."
  TOKEN=$(curl -s -m 5 -H "${MD_HDR}" "${MD}/instance/service-accounts/default/token" \
          | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')
  PACKER_PW=$(curl -s -m 15 -H "Authorization: Bearer ${TOKEN}" \
    "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${WINRM_SECRET}/versions/latest:access" \
    | python3 -c 'import sys,json,base64; print(base64.b64decode(json.load(sys.stdin)["payload"]["data"]).decode())')
fi

if [ -z "${PACKER_PW}" ]; then
  echo "FATAL: could not retrieve the WinRM password by either method."
  exit 1
fi
echo "WinRM password retrieved (${#PACKER_PW} chars)."
export PACKER_PW

# ── Packer logging ───────────────────────────────────────────
export PACKER_LOG=1

# ── Validate template ────────────────────────────────────────
echo "Validating Packer template..."
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

# ── Run Packer build ─────────────────────────────────────────
echo "Starting Packer build..."
packer build \
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

echo "Packer build completed successfully."

# ── Deprecate older images ───────────────────────────────────
# ── Deprecate older images ───────────────────────────────────
echo "Deprecating older images in family ${IMAGE_FAMILY}..."

LATEST_IMAGE=$(gcloud compute images list \
  --project="${PROJECT_ID}" \
  --filter="family=${IMAGE_FAMILY}" \
  --sort-by="~creationTimestamp" \
  --format="value(name)" \
  --limit=1)

if [ -n "${LATEST_IMAGE}" ]; then
  # Only deprecates Phase 1 base images (nmfs-windows-2025-[timestamp])
  # Never touches oracle-client images
  OLD_IMAGES=$(gcloud compute images list \
    --project="${PROJECT_ID}" \
    --filter="family=${IMAGE_FAMILY} AND name~'^nmfs-windows-2025-[0-9]' AND name!=${LATEST_IMAGE}" \
    --format="value(name)")

  while IFS= read -r IMAGE; do
    [ -z "$IMAGE" ] && continue
    gcloud compute images deprecate "${IMAGE}" \
      --project="${PROJECT_ID}" \
      --state=DEPRECATED \
      --replacement="${LATEST_IMAGE}"
  done <<< "${OLD_IMAGES}"
fi

echo "Phase 1 build complete: ${LATEST_IMAGE}"
