#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# docker-entrypoint.sh
#
# Parameterized entrypoint for the Windows image builder container.
#
# Supports TWO modes:
#   1. JSON mode  – set REQUEST_JSON_GCS to a GCS path (gs://bucket/requests/req.json)
#                   Triggered by Eventarc when a JSON file lands in the bucket.
#   2. ENV mode   – set individual INSTALL_* env vars (backward-compatible)
#
# Metadata tracking:
#   Writes status JSON to GCS_STATUS_BUCKET/status/<request_id>.json
#   at each stage: RECEIVED → IN_PROGRESS → COMPLETED / FAILED
#
# VM creation:
#   If create_vm=true in the JSON, creates a Compute Engine VM from the image.
#
# Email notification:
#   Publishes to PUBSUB_TOPIC on completion for Cloud Function to send email.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

echo "Phase 2: Parameterized Windows Image Builder — $(date -u)"
packer version

# ── Resolve infra variables ──────────────────────────────────────────────────
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

# ── Metadata / notification config ──────────────────────────────────────────
GCS_STATUS_BUCKET="${GCS_STATUS_BUCKET:-}"
PUBSUB_TOPIC="${PUBSUB_TOPIC:-image-builder-notifications}"
REQUEST_JSON_GCS="${REQUEST_JSON_GCS:-}"

# ── Helper: convert to strict boolean ────────────────────────────────────────
to_bool() {
  local val
  val=$(echo "${1:-false}" | tr '[:upper:]' '[:lower:]')
  case "$val" in
    true|1|yes) echo "true" ;;
    *)           echo "false" ;;
  esac
}

# ── Helper: write status metadata to GCS ─────────────────────────────────────
write_status() {
  local status="$1"
  local extra="${2:-}"

  if [ -z "${GCS_STATUS_BUCKET}" ] || [ -z "${REQUEST_ID:-}" ]; then
    return 0
  fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local status_json
  status_json=$(jq -n \
    --arg request_id "${REQUEST_ID}" \
    --arg status "${status}" \
    --arg requester_name "${REQUESTER_NAME:-unknown}" \
    --arg requester_email "${REQUESTER_EMAIL:-unknown}" \
    --arg requester_team "${REQUESTER_TEAM:-unknown}" \
    --arg requested_at "${REQUESTED_AT:-${now}}" \
    --arg updated_at "${now}" \
    --arg image_family "${IMAGE_FAMILY}" \
    --arg project_id "${PROJECT_ID}" \
    --arg zone "${ZONE}" \
    --arg image_name "${BUILT_IMAGE_NAME:-pending}" \
    --arg vm_name "${CREATED_VM_NAME:-none}" \
    --argjson create_vm "$([ "${CREATE_VM:-false}" = "true" ] && echo true || echo false)" \
    --argjson software "${SOFTWARE_JSON:-{}}" \
    --arg extra "${extra}" \
    '{
      request_id: $request_id,
      status: $status,
      requester: {
        name: $requester_name,
        email: $requester_email,
        team: $requester_team
      },
      requested_at: $requested_at,
      updated_at: $updated_at,
      config: {
        image_family: $image_family,
        project_id: $project_id,
        zone: $zone,
        create_vm: $create_vm,
        software: $software
      },
      result: {
        image_name: $image_name,
        vm_name: $vm_name
      },
      message: $extra
    }')

  local status_path="gs://${GCS_STATUS_BUCKET}/status/${REQUEST_ID}.json"
  echo "${status_json}" | gsutil -q cp - "${status_path}"
  echo "[STATUS] ${status} → ${status_path}"
}

# ── Helper: publish notification to Pub/Sub ──────────────────────────────────
publish_notification() {
  local status="$1"
  local message="$2"

  if [ -z "${PUBSUB_TOPIC:-}" ]; then
    echo "[NOTIFY] No PUBSUB_TOPIC set — skipping notification"
    return 0
  fi

  local payload
  payload=$(jq -n \
    --arg request_id "${REQUEST_ID:-unknown}" \
    --arg status "${status}" \
    --arg requester_name "${REQUESTER_NAME:-unknown}" \
    --arg requester_email "${REQUESTER_EMAIL:-unknown}" \
    --arg image_name "${BUILT_IMAGE_NAME:-unknown}" \
    --arg vm_name "${CREATED_VM_NAME:-none}" \
    --arg message "${message}" \
    --arg project_id "${PROJECT_ID}" \
    '{
      request_id: $request_id,
      status: $status,
      requester_name: $requester_name,
      requester_email: $requester_email,
      image_name: $image_name,
      vm_name: $vm_name,
      message: $message,
      project_id: $project_id
    }')

  gcloud pubsub topics publish "${PUBSUB_TOPIC}" \
    --project="${PROJECT_ID}" \
    --message="${payload}" \
    --attribute="request_id=${REQUEST_ID:-unknown},status=${status}" \
    || echo "[WARN] Failed to publish Pub/Sub notification"
}

# ══════════════════════════════════════════════════════════════════════════════
# MODE DETECTION: JSON from GCS vs environment variables
# ══════════════════════════════════════════════════════════════════════════════

# Default all component flags
INSTALL_ORACLE="false"
INSTALL_RSTUDIO="false"
INSTALL_CONDA="false"
INSTALL_CHROME="false"
INSTALL_GIT="false"
INSTALL_PYTHON="false"
INSTALL_JUPYTERLAB="false"
INSTALL_POWERSHELL_CORE="false"
INSTALL_PYCHARM="false"
INSTALL_VISUAL_STUDIO="false"
INSTALL_PARAVIEW="false"
INSTALL_ECHOVIEW="false"
INSTALL_MATLAB="false"
INSTALL_RSTUDIO_PRO="false"
INSTALL_POSITRON="false"
INSTALL_ANACONDA="false"
INSTALL_GPU_DRIVERS="false"
INSTALL_AALIBRARY="false"
INSTALL_ECHOSMS="false"
INSTALL_ECHOSTACK="false"
INSTALL_GCP_UTILITIES="false"
INSTALL_EXCEL="false"

# Metadata defaults
REQUEST_ID=""
REQUESTER_NAME=""
REQUESTER_EMAIL=""
REQUESTER_TEAM=""
REQUESTED_AT=""
CREATE_VM="false"
KEEP_IMAGE="true"
IMAGE_CONFIG_NAME=""
SOFTWARE_JSON="{}"
BUILT_IMAGE_NAME=""
CREATED_VM_NAME=""

if [ -n "${REQUEST_JSON_GCS}" ]; then
  # ── JSON MODE ──────────────────────────────────────────────────────────────
  echo "[MODE] JSON — reading config from: ${REQUEST_JSON_GCS}"

  REQUEST_JSON_LOCAL="/tmp/request.json"
  gsutil cp "${REQUEST_JSON_GCS}" "${REQUEST_JSON_LOCAL}"

  if [ ! -f "${REQUEST_JSON_LOCAL}" ]; then
    echo "[ERROR] Failed to download request JSON from ${REQUEST_JSON_GCS}"
    exit 1
  fi

  # Parse requester metadata
  REQUEST_ID=$(jq -r '.request_id // empty' "${REQUEST_JSON_LOCAL}")
  if [ -z "${REQUEST_ID}" ]; then
    REQUEST_ID="req-$(date +%s)-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' ')"
  fi
  REQUESTER_NAME=$(jq -r '.requester.name // "unknown"' "${REQUEST_JSON_LOCAL}")
  REQUESTER_EMAIL=$(jq -r '.requester.email // "unknown"' "${REQUEST_JSON_LOCAL}")
  REQUESTER_TEAM=$(jq -r '.requester.team // "unknown"' "${REQUEST_JSON_LOCAL}")
  REQUESTED_AT=$(jq -r '.requested_at // empty' "${REQUEST_JSON_LOCAL}")
  if [ -z "${REQUESTED_AT}" ]; then
    REQUESTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  fi

  # Parse image config
  IMAGE_CONFIG_NAME=$(jq -r '.image_config.image_name // empty' "${REQUEST_JSON_LOCAL}")
  CREATE_VM=$(jq -r '.image_config.create_vm // false' "${REQUEST_JSON_LOCAL}")
  KEEP_IMAGE=$(jq -r '.image_config.keep_image // true' "${REQUEST_JSON_LOCAL}")

  # Override IMAGE_FAMILY if custom name provided
  if [ -n "${IMAGE_CONFIG_NAME}" ]; then
    IMAGE_FAMILY="${IMAGE_CONFIG_NAME}"
  fi

  # Parse software flags
  SOFTWARE_JSON=$(jq -c '.image_config.software // {}' "${REQUEST_JSON_LOCAL}")

  INSTALL_ORACLE=$(to_bool "$(jq -r '.image_config.software.oracle_client // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_RSTUDIO=$(to_bool "$(jq -r '.image_config.software.rstudio // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_CONDA=$(to_bool "$(jq -r '.image_config.software.conda // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_CHROME=$(to_bool "$(jq -r '.image_config.software.chrome // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_GIT=$(to_bool "$(jq -r '.image_config.software.git // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_PYTHON=$(to_bool "$(jq -r '.image_config.software.python // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_JUPYTERLAB=$(to_bool "$(jq -r '.image_config.software.jupyterlab // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_POWERSHELL_CORE=$(to_bool "$(jq -r '.image_config.software.powershell_core // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_PYCHARM=$(to_bool "$(jq -r '.image_config.software.pycharm_community // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_VISUAL_STUDIO=$(to_bool "$(jq -r '.image_config.software.visual_studio_community // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_PARAVIEW=$(to_bool "$(jq -r '.image_config.software.paraview // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_ECHOVIEW=$(to_bool "$(jq -r '.image_config.software.echoview // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_MATLAB=$(to_bool "$(jq -r '.image_config.software.matlab // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_RSTUDIO_PRO=$(to_bool "$(jq -r '.image_config.software.rstudio_pro // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_POSITRON=$(to_bool "$(jq -r '.image_config.software.positron // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_ANACONDA=$(to_bool "$(jq -r '.image_config.software.anaconda // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_GPU_DRIVERS=$(to_bool "$(jq -r '.image_config.software.gpu_drivers // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_AALIBRARY=$(to_bool "$(jq -r '.image_config.software.aalibrary // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_ECHOSMS=$(to_bool "$(jq -r '.image_config.software.echosms // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_ECHOSTACK=$(to_bool "$(jq -r '.image_config.software.echostack // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_GCP_UTILITIES=$(to_bool "$(jq -r '.image_config.software.gcp_utilities // false' "${REQUEST_JSON_LOCAL}")")
  INSTALL_EXCEL=$(to_bool "$(jq -r '.image_config.software.excel // false' "${REQUEST_JSON_LOCAL}")")

  echo "[JSON] Request ID    : ${REQUEST_ID}"
  echo "[JSON] Requester     : ${REQUESTER_NAME} <${REQUESTER_EMAIL}> (${REQUESTER_TEAM})"
  echo "[JSON] Image Name    : ${IMAGE_CONFIG_NAME:-default}"
  echo "[JSON] Create VM     : ${CREATE_VM}"
  echo "[JSON] Keep Image    : ${KEEP_IMAGE}"

  # Write initial status
  write_status "RECEIVED" "Request received from ${REQUESTER_NAME}"

else
  # ── ENV MODE (backward compatible) ─────────────────────────────────────────
  echo "[MODE] ENV — using environment variables"

  REQUEST_ID="env-$(date +%s)"

  INSTALL_ORACLE=$(to_bool "${INSTALL_ORACLE:-false}")
  INSTALL_RSTUDIO=$(to_bool "${INSTALL_RSTUDIO:-false}")
  INSTALL_CONDA=$(to_bool "${INSTALL_CONDA:-false}")
  INSTALL_CHROME=$(to_bool "${INSTALL_CHROME:-false}")
  INSTALL_GIT=$(to_bool "${INSTALL_GIT:-false}")
  INSTALL_PYTHON=$(to_bool "${INSTALL_PYTHON:-false}")
  INSTALL_JUPYTERLAB=$(to_bool "${INSTALL_JUPYTERLAB:-false}")
  INSTALL_POWERSHELL_CORE=$(to_bool "${INSTALL_POWERSHELL_CORE:-false}")
  INSTALL_PYCHARM=$(to_bool "${INSTALL_PYCHARM:-false}")
  INSTALL_VISUAL_STUDIO=$(to_bool "${INSTALL_VISUAL_STUDIO:-false}")
  INSTALL_PARAVIEW=$(to_bool "${INSTALL_PARAVIEW:-false}")
  INSTALL_ECHOVIEW=$(to_bool "${INSTALL_ECHOVIEW:-false}")
  INSTALL_MATLAB=$(to_bool "${INSTALL_MATLAB:-false}")
  INSTALL_RSTUDIO_PRO=$(to_bool "${INSTALL_RSTUDIO_PRO:-false}")
  INSTALL_POSITRON=$(to_bool "${INSTALL_POSITRON:-false}")
  INSTALL_ANACONDA=$(to_bool "${INSTALL_ANACONDA:-false}")
  INSTALL_GPU_DRIVERS=$(to_bool "${INSTALL_GPU_DRIVERS:-false}")
  INSTALL_AALIBRARY=$(to_bool "${INSTALL_AALIBRARY:-false}")
  INSTALL_ECHOSMS=$(to_bool "${INSTALL_ECHOSMS:-false}")
  INSTALL_ECHOSTACK=$(to_bool "${INSTALL_ECHOSTACK:-false}")
  INSTALL_GCP_UTILITIES=$(to_bool "${INSTALL_GCP_UTILITIES:-false}")
  INSTALL_EXCEL=$(to_bool "${INSTALL_EXCEL:-false}")
fi

# ── Log resolved flags ───────────────────────────────────────────────────────
echo "──────────────────────────────────────────────"
echo "  Installation components:"
echo "    Oracle Client    : ${INSTALL_ORACLE}"
echo "    RStudio (OSS)    : ${INSTALL_RSTUDIO}"
echo "    Conda/Miniconda  : ${INSTALL_CONDA}"
echo "    Chrome           : ${INSTALL_CHROME}"
echo "    Git/GitHub Desk  : ${INSTALL_GIT}"
echo "    Python           : ${INSTALL_PYTHON}"
echo "    JupyterLab       : ${INSTALL_JUPYTERLAB}"
echo "    PowerShell Core  : ${INSTALL_POWERSHELL_CORE}"
echo "    PyCharm          : ${INSTALL_PYCHARM}"
echo "    Visual Studio    : ${INSTALL_VISUAL_STUDIO}"
echo "    ParaView         : ${INSTALL_PARAVIEW}"
echo "    Echoview         : ${INSTALL_ECHOVIEW}"
echo "    MATLAB           : ${INSTALL_MATLAB}"
echo "    RStudio Pro      : ${INSTALL_RSTUDIO_PRO}"
echo "    Positron         : ${INSTALL_POSITRON}"
echo "    Anaconda         : ${INSTALL_ANACONDA}"
echo "    GPU Drivers      : ${INSTALL_GPU_DRIVERS}"
echo "    AA-SI aalibrary  : ${INSTALL_AALIBRARY}"
echo "    EchoSMs          : ${INSTALL_ECHOSMS}"
echo "    EchoStack        : ${INSTALL_ECHOSTACK}"
echo "    GCP Utilities    : ${INSTALL_GCP_UTILITIES}"
echo "    Excel            : ${INSTALL_EXCEL}"
echo "  Infra:"
echo "    PROJECT_ID       : ${PROJECT_ID}"
echo "    IMAGE_FAMILY     : ${IMAGE_FAMILY}"
echo "    ZONE             : ${ZONE}"
echo "──────────────────────────────────────────────"

# ── Guard: at least one component must be selected ───────────────────────────
ALL_FALSE=true
for flag in \
  INSTALL_ORACLE INSTALL_RSTUDIO INSTALL_CONDA INSTALL_CHROME INSTALL_GIT \
  INSTALL_PYTHON INSTALL_JUPYTERLAB INSTALL_POWERSHELL_CORE INSTALL_PYCHARM \
  INSTALL_VISUAL_STUDIO INSTALL_PARAVIEW INSTALL_ECHOVIEW INSTALL_MATLAB \
  INSTALL_RSTUDIO_PRO INSTALL_POSITRON INSTALL_ANACONDA INSTALL_GPU_DRIVERS \
  INSTALL_AALIBRARY INSTALL_ECHOSMS INSTALL_ECHOSTACK INSTALL_GCP_UTILITIES \
  INSTALL_EXCEL; do
  if [ "${!flag}" = "true" ]; then
    ALL_FALSE=false
    break
  fi
done

if [ "${ALL_FALSE}" = "true" ]; then
  echo "[WARN] No components selected – exiting early."
  write_status "FAILED" "No software components selected"
  publish_notification "FAILED" "No software components were selected in the request."
  exit 0
fi

# ── Compute software fingerprint (for duplicate detection) ───────────────────
# Must match the logic in process-request Cloud Function
ENABLED_SOFTWARE=""
for pair in \
  "anaconda:${INSTALL_ANACONDA}" "aalibrary:${INSTALL_AALIBRARY}" \
  "chrome:${INSTALL_CHROME}" "conda:${INSTALL_CONDA}" \
  "echoview:${INSTALL_ECHOVIEW}" "echosms:${INSTALL_ECHOSMS}" \
  "echostack:${INSTALL_ECHOSTACK}" "excel:${INSTALL_EXCEL}" \
  "gcp_utilities:${INSTALL_GCP_UTILITIES}" "git:${INSTALL_GIT}" \
  "gpu_drivers:${INSTALL_GPU_DRIVERS}" "jupyterlab:${INSTALL_JUPYTERLAB}" \
  "matlab:${INSTALL_MATLAB}" "oracle_client:${INSTALL_ORACLE}" \
  "paraview:${INSTALL_PARAVIEW}" "positron:${INSTALL_POSITRON}" \
  "powershell_core:${INSTALL_POWERSHELL_CORE}" "pycharm_community:${INSTALL_PYCHARM}" \
  "python:${INSTALL_PYTHON}" "rstudio:${INSTALL_RSTUDIO}" \
  "rstudio_pro:${INSTALL_RSTUDIO_PRO}" "visual_studio_community:${INSTALL_VISUAL_STUDIO}"; do
  key="${pair%%:*}"
  val="${pair##*:}"
  if [ "${val}" = "true" ]; then
    ENABLED_SOFTWARE="${ENABLED_SOFTWARE:+${ENABLED_SOFTWARE},}${key}"
  fi
done

SOFTWARE_FINGERPRINT=$(echo -n "${ENABLED_SOFTWARE}" | sha256sum | cut -c1-16)
echo "[FINGERPRINT] ${SOFTWARE_FINGERPRINT} (${ENABLED_SOFTWARE})"

# ── Update status: IN_PROGRESS ───────────────────────────────────────────────
write_status "IN_PROGRESS" "Building image with selected software"

# ── Fetch WinRM secret ───────────────────────────────────────────────────────
PACKER_PW=$(gcloud secrets versions access latest \
  --project "${PROJECT_ID}" \
  --secret "${WINRM_SECRET}")
export PACKER_PW

# ── Packer debug logging ─────────────────────────────────────────────────────
export PACKER_LOG=1
export PACKER_LOG_PATH="/tmp/packer-debug.log"

# ── Sanity-check template ────────────────────────────────────────────────────
if [ ! -f "${PACKER_TEMPLATE}" ]; then
  echo "[ERROR] Packer template not found: ${PACKER_TEMPLATE}"
  write_status "FAILED" "Packer template not found: ${PACKER_TEMPLATE}"
  exit 1
fi

# ── Packer init ──────────────────────────────────────────────────────────────
packer init "${PACKER_TEMPLATE}"

# ── Common packer -var flags ─────────────────────────────────────────────────
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
  -var "install_chrome=${INSTALL_CHROME}"
  -var "install_git=${INSTALL_GIT}"
  -var "install_python=${INSTALL_PYTHON}"
  -var "install_jupyterlab=${INSTALL_JUPYTERLAB}"
  -var "install_powershell_core=${INSTALL_POWERSHELL_CORE}"
  -var "install_pycharm=${INSTALL_PYCHARM}"
  -var "install_visual_studio=${INSTALL_VISUAL_STUDIO}"
  -var "install_paraview=${INSTALL_PARAVIEW}"
  -var "install_echoview=${INSTALL_ECHOVIEW}"
  -var "install_matlab=${INSTALL_MATLAB}"
  -var "install_rstudio_pro=${INSTALL_RSTUDIO_PRO}"
  -var "install_positron=${INSTALL_POSITRON}"
  -var "install_anaconda=${INSTALL_ANACONDA}"
  -var "install_gpu_drivers=${INSTALL_GPU_DRIVERS}"
  -var "install_aalibrary=${INSTALL_AALIBRARY}"
  -var "install_echosms=${INSTALL_ECHOSMS}"
  -var "install_echostack=${INSTALL_ECHOSTACK}"
  -var "install_gcp_utilities=${INSTALL_GCP_UTILITIES}"
  -var "install_excel=${INSTALL_EXCEL}"
)

# ── Validate ─────────────────────────────────────────────────────────────────
packer validate "${PACKER_VARS[@]}" "${PACKER_TEMPLATE}"

# ── gcloud auth check ────────────────────────────────────────────────────────
if ! gcloud auth list 2>&1 | grep -q "ACTIVE"; then
  echo "[ERROR] gcloud is not authenticated"
  write_status "FAILED" "gcloud is not authenticated"
  exit 1
fi

# ── Packer build ─────────────────────────────────────────────────────────────
if ! packer build "${PACKER_VARS[@]}" "${PACKER_TEMPLATE}"; then
  echo "[ERROR] Packer build failed"
  [ -f /tmp/packer-debug.log ] && tail -100 /tmp/packer-debug.log
  write_status "FAILED" "Packer build failed — check logs"
  publish_notification "FAILED" "Image build failed for request ${REQUEST_ID}. Check Cloud Run logs."
  exit 1
fi

# ── Get the built image name ─────────────────────────────────────────────────
BUILT_IMAGE_NAME=$(gcloud compute images list \
  --project="${PROJECT_ID}" \
  --filter="family=${IMAGE_FAMILY}" \
  --sort-by="~creationTimestamp" \
  --format="value(name)" \
  --limit=1)

echo "Built image: ${BUILT_IMAGE_NAME}"

# ── Label image with software fingerprint (for duplicate detection) ──────────
if [ -n "${BUILT_IMAGE_NAME}" ] && [ -n "${SOFTWARE_FINGERPRINT}" ]; then
  echo "[LABEL] Adding software-fingerprint=${SOFTWARE_FINGERPRINT} to ${BUILT_IMAGE_NAME}"
  gcloud compute images add-labels "${BUILT_IMAGE_NAME}" \
    --project="${PROJECT_ID}" \
    --labels="software-fingerprint=${SOFTWARE_FINGERPRINT},request-id=${REQUEST_ID},built-by=image-builder" \
    || echo "[WARN] Failed to add labels to image"
fi

# ── Deprecate old images ─────────────────────────────────────────────────────
if [ -n "${BUILT_IMAGE_NAME}" ]; then
  OLD_IMAGES=$(gcloud compute images list \
    --project="${PROJECT_ID}" \
    --filter="family=${IMAGE_FAMILY} AND name!=${BUILT_IMAGE_NAME}" \
    --format="value(name)")

  while IFS= read -r IMAGE; do
    [ -z "$IMAGE" ] && continue
    gcloud compute images deprecate "${IMAGE}" \
      --project="${PROJECT_ID}" \
      --state=DEPRECATED \
      --replacement="${BUILT_IMAGE_NAME}"
  done <<< "${OLD_IMAGES}"
fi

# ══════════════════════════════════════════════════════════════════════════════
# VM CREATION (if requested)
# ══════════════════════════════════════════════════════════════════════════════
CREATED_VM_NAME=""

if [ "$(to_bool "${CREATE_VM}")" = "true" ] && [ -n "${BUILT_IMAGE_NAME}" ]; then
  echo "[VM] Creating VM from image: ${BUILT_IMAGE_NAME}"

  # Generate VM name from image family or config name
  VM_NAME_BASE="${IMAGE_CONFIG_NAME:-${IMAGE_FAMILY}}"
  # Sanitize: lowercase, replace non-alphanum with dash, truncate
  VM_NAME=$(echo "${VM_NAME_BASE}-vm" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | cut -c1-60)
  CREATED_VM_NAME="${VM_NAME}"

  # Determine machine type for VM (use GPU type if GPU drivers requested)
  VM_MACHINE_TYPE="${MACHINE_TYPE}"
  ACCELERATOR_FLAG=""
  if [ "${INSTALL_GPU_DRIVERS}" = "true" ]; then
    VM_MACHINE_TYPE="n1-standard-8"
    ACCELERATOR_FLAG="--accelerator=type=nvidia-tesla-t4,count=1 --maintenance-policy=TERMINATE"
  fi

  if gcloud compute instances create "${VM_NAME}" \
    --project="${PROJECT_ID}" \
    --zone="${ZONE}" \
    --machine-type="${VM_MACHINE_TYPE}" \
    --image="${BUILT_IMAGE_NAME}" \
    --image-project="${PROJECT_ID}" \
    --boot-disk-size=250GB \
    --network="app-network" \
    --subnet="app-subnet1" \
    --no-address \
    --service-account="${SERVICE_ACCOUNT_EMAIL}" \
    --scopes="cloud-platform" \
    --shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    ${ACCELERATOR_FLAG} \
    --labels="created-by=image-builder,request-id=${REQUEST_ID}" \
    --metadata="enable-oslogin=TRUE"; then
    echo "[VM] VM created successfully: ${VM_NAME}"
  else
    echo "[WARN] VM creation failed — image is still available: ${BUILT_IMAGE_NAME}"
    CREATED_VM_NAME="FAILED"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# COMPLETION: write final status + send notification
# ══════════════════════════════════════════════════════════════════════════════
write_status "COMPLETED" "Image build and provisioning completed successfully"

# Build notification message
NOTIFY_MSG="Your custom Windows image '${BUILT_IMAGE_NAME}' has been created successfully in project '${PROJECT_ID}'."
if [ -n "${CREATED_VM_NAME}" ] && [ "${CREATED_VM_NAME}" != "FAILED" ]; then
  NOTIFY_MSG="${NOTIFY_MSG} VM '${CREATED_VM_NAME}' has been created from this image in zone '${ZONE}'."
elif [ "${CREATED_VM_NAME}" = "FAILED" ]; then
  NOTIFY_MSG="${NOTIFY_MSG} VM creation was requested but failed. The image is available in the image library."
fi

publish_notification "COMPLETED" "${NOTIFY_MSG}"

echo "══════════════════════════════════════════════════════════════"
echo "  BUILD COMPLETE"
echo "  Image      : ${BUILT_IMAGE_NAME}"
echo "  VM         : ${CREATED_VM_NAME:-not requested}"
echo "  Request ID : ${REQUEST_ID}"
echo "  Requester  : ${REQUESTER_NAME:-N/A} <${REQUESTER_EMAIL:-N/A}>"
echo "══════════════════════════════════════════════════════════════"
