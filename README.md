# Windows Image Builder - Automated GCP Infrastructure

Automated Windows Server 2022 image builder with VM provisioning. Drop a JSON request in a GCS bucket and the pipeline builds a custom Windows image, creates a VM, sets up a workstation user, and notifies the requester via email.

## Architecture

```
JSON request dropped in GCS bucket
  |
  v
Eventarc -> Cloud Function: process-request
  |- Detects client JSON format, normalizes to pipeline format
  |- Computes software fingerprint (SHA256)
  |- Checks for duplicate images
  |- DUPLICATE + create_vm? -> Skip build, trigger VM-only creation
  |- DUPLICATE + no VM?     -> Write status, skip
  '- NEW?                   -> Trigger full build + VM creation
        |
        v
Cloud Run Job: windows-image-builder
  |- Packer builds Windows VM with selected software (or skips if duplicate)
  |- Labels image with software fingerprint
  |- Creates VM from image (requested machine type + disk size)
  |- Creates workstation user (firstname_lastname, Standard User + RDP)
  |- Sends email notification with credentials
  '- Writes build status to GCS
```

## Components

| Component | Type | Purpose |
|-----------|------|---------|
| `process-request` | Cloud Function | Normalizes JSON, duplicate detection, triggers builds |
| `windows-image-builder` | Cloud Run Job | Packer build + VM creation + user setup |
| `image-builder-requests` | GCS Bucket | Request/status/audit storage |

---

# Deployment Guide

## Prerequisites

### 1. GCP Project Setup

```bash
export PROJECT_ID="your-project-id"
export REGION="us-east4"

gcloud config set project $PROJECT_ID
```

### 2. Enable Required APIs

```bash
gcloud services enable \
  compute.googleapis.com \
  run.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com \
  storage.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  logging.googleapis.com \
  iam.googleapis.com \
  --project=$PROJECT_ID
```

### 3. VPC Network

The pipeline needs a VPC network with:
- A subnet in the target region
- Firewall rule allowing WinRM (TCP 5986) from IAP range
- Cloud NAT for external access (email notifications, software downloads)

```bash
# Create firewall rule for Packer WinRM via IAP
gcloud compute firewall-rules create allow-winrm-iap \
  --network=your-network \
  --allow=tcp:5986 \
  --source-ranges=35.235.240.0/20 \
  --target-tags=winrm \
  --project=$PROJECT_ID
```

**For Shared VPC:** Set `shared_vpc_host_project` in `terraform.tfvars` (see Configuration section).

### 4. Base Image

A Windows Server 2022 base image must exist in your project under family `nmfs-windows-2022`.

```bash
# Verify base image exists
gcloud compute images list --project=$PROJECT_ID --filter="family=nmfs-windows-2022"
```

### 5. Artifact Registry

```bash
gcloud artifacts repositories create packer-images \
  --repository-format=docker \
  --location=$REGION \
  --project=$PROJECT_ID
```

### 6. Software Binaries Bucket

Software installed from GCS (Oracle Client, MATLAB, ParaView, etc.) needs binaries uploaded:

```bash
gsutil mb -l $REGION gs://org-sec-agents-bucket

# Upload binaries:
# gs://org-sec-agents-bucket/oracle-client/instantclient-basic-windows.zip
# gs://org-sec-agents-bucket/ParaView-6.2.0-RC1-Windows-Python3.12-msvc2017-AMD64.msi
# gs://org-sec-agents-bucket/matlab/matlab_installer.exe
# etc.
```

---

## Service Account Setup

```bash
# Create service account
gcloud iam service-accounts create packer-win-sa \
  --display-name="Packer Windows Image Builder SA" \
  --project=$PROJECT_ID

SA_EMAIL="packer-win-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# Assign roles
ROLES=(
  "roles/storage.admin"
  "roles/secretmanager.secretAccessor"
  "roles/logging.logWriter"
  "roles/compute.admin"
  "roles/artifactregistry.writer"
  "roles/iam.serviceAccountUser"
  "roles/iap.tunnelResourceAccessor"
  "roles/cloudbuild.builds.builder"
  "roles/run.developer"
  "roles/run.invoker"
  "roles/eventarc.eventReceiver"
  "roles/cloudfunctions.invoker"
)

for ROLE in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${ROLE}" \
    --condition=None
done

# Eventarc service agent permissions
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com" \
  --role="roles/eventarc.serviceAgent"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com" \
  --role="roles/pubsub.publisher"
```

---

## Secret Manager Setup

```bash
# 1. WinRM Password (required for Packer)
WINRM_PW=$(openssl rand -base64 24)
gcloud secrets create packer-winrm-password --project=$PROJECT_ID
echo -n "$WINRM_PW" | gcloud secrets versions add packer-winrm-password \
  --data-file=- --project=$PROJECT_ID

# 2. Gmail App Password (optional — for email notifications)
gcloud secrets create gmail-app-password --project=$PROJECT_ID
echo -n "YOUR-GMAIL-APP-PASSWORD" | gcloud secrets versions add gmail-app-password \
  --data-file=- --project=$PROJECT_ID
```

---

## Configuration

Edit `terraform/terraform.tfvars`:

```hcl
project_id               = "your-project-id"
region                    = "us-east4"

# Network
vm_network               = "your-vpc-network"
vm_subnet                = "your-subnet"
shared_vpc_host_project  = ""                    # Set if using Shared VPC

# Email notifications (optional)
gmail_sender_email       = "notifications@yourdomain.com"

# All install_* flags default to false — controlled by JSON requests
```

---

## Deployment Steps

```bash
# 1. Clone the repo
git clone <repo-url>
cd windows-image-infra

# 2. Update terraform/terraform.tfvars with your values

# 3. Build Docker image
gcloud builds submit --config=cloudbuild-docker.yaml . --project=$PROJECT_ID

# 4. Deploy infrastructure
cd terraform
terraform init
terraform plan
terraform apply
```

---

## JSON Request Format

Drop a JSON file into `gs://{project-id}-image-builder-requests/requests/`:

```json
{
  "submitter_name": "Drew Beling",
  "submitter_email": "drew.beling@noaa.gov",
  "ticket_number": "CLOUD-586",
  "request_type": "Cloud VM Provisioning",
  "status": "Waiting for support",
  "created": "2026-07-29T18:39:04.000+0000",
  "summary": "Demo for Rajinder",
  "fmc": "OCIO",
  "workstation_size": "Large - (16 – 32 vCPU | RAM: 64 – 128 GB | Storage: 500GB – 1TB)",
  "software_packages": "FireFox, Oracle Drivers",
  "additional_unlisted_software": "Git and gcloud SDK and VS Code"
}
```

### Required Fields

| Field | Description | Example |
|---|---|---|
| `submitter_name` | Full name (VM user created as `firstname_lastname`) | `"Drew Beling"` |
| `submitter_email` | Email for build notifications | `"drew.beling@noaa.gov"` |
| `ticket_number` | Ticket/request ID | `"CLOUD-586"` |
| `software_packages` | Comma-separated software list | `"Chrome, Oracle Drivers, Git"` |

### Optional Fields

| Field | Description | Default |
|---|---|---|
| `workstation_size` | VM size (just include Small/Medium/Large/XLarge in string) | Medium |
| `fmc` | Team/org name | `"unknown"` |
| `request_type` | Request category | `""` |
| `status` | Ticket status | `""` |
| `summary` | Request description | `""` |
| `created` | Timestamp | Current time |
| `additional_unlisted_software` | Logged only, not auto-installed | `""` |

---

## Workstation Size Mapping

Your existing format works as-is (e.g., `"Large - (16 – 32 vCPU | RAM: 64 – 128 GB | Storage: 500GB – 1TB)"`). The system extracts the size keyword automatically.

| Size keyword | Machine Type | Disk Size |
|---|---|---|
| Small | `e2-standard-4` (4 vCPU, 16GB RAM) | 250GB |
| Medium | `e2-standard-8` (8 vCPU, 32GB RAM) | 250GB |
| Large | `e2-standard-16` (16 vCPU, 64GB RAM) | 500GB |
| XLarge | `e2-standard-32` (32 vCPU, 128GB RAM) | 1TB |

---

## Supported Software (22 packages)

| Software Name in JSON | Internal Key | Install Method |
|---|---|---|
| Chrome, Google Chrome, FireFox | `chrome` | Chocolatey |
| Git, GitHub Desktop | `git` | Chocolatey |
| Python | `python` | Chocolatey |
| JupyterLab, Jupyter | `jupyterlab` | pip |
| Conda, Miniconda | `conda` | Chocolatey |
| Anaconda | `anaconda` | Chocolatey |
| RStudio | `rstudio` | Chocolatey |
| RStudio Pro | `rstudio_pro` | GCS binary |
| PyCharm, PyCharm Community | `pycharm_community` | Chocolatey |
| Visual Studio, Visual Studio Community, VS Code | `visual_studio_community` | Chocolatey |
| PowerShell, PowerShell Core | `powershell_core` | Chocolatey |
| Positron | `positron` | GCS binary |
| ParaView | `paraview` | GCS (MSI) |
| Echoview | `echoview` | GCS binary |
| EchoSMs | `echosms` | GCS binary |
| EchoStack | `echostack` | GCS binary |
| MATLAB | `matlab` | GCS binary |
| GPU Drivers, NVIDIA Drivers | `gpu_drivers` | GCS binary |
| Oracle Client, Oracle Drivers, Oracle | `oracle_client` | GCS binary |
| aalibrary, AA Library | `aalibrary` | GCS binary |
| GCP Utilities, gcloud SDK, gcloud | `gcp_utilities` | gcloud SDK |
| Excel, Microsoft Excel | `excel` | Office Deployment Tool |

---

## What Happens Automatically

1. **JSON dropped in bucket** -- Cloud Function triggers
2. **Client JSON normalized** -- flat format converted to pipeline format
3. **Software fingerprint check** -- if same software combo image already exists:
   - `create_vm=true`: skips image build, creates VM from existing image
   - No VM needed: returns duplicate status, no build
4. **New software combo** -- Packer builds custom Windows image (~20-40 min)
5. **VM created** with:
   - Requested machine type and disk size
   - Workstation user (`firstname_lastname`) as Standard User
   - User added to Remote Desktop Users group
   - Windows hostname set to VM name (truncated to 15 chars)
   - Service account attached
   - Network/subnet from config (supports Shared VPC)
6. **Email notification** sent to `submitter_email` with:
   - Image name, VM name, project, zone
   - Workstation user credentials (username + password)

---

## GCS Bucket Structure

```
gs://{PROJECT_ID}-image-builder-requests/
  requests/          # Input: drop JSON files here (triggers pipeline)
  processed/         # Enriched JSON passed to Cloud Run Job
  audit/             # Permanent audit trail
  status/            # Build status per request ID
```

---

## Duplicate Detection

The system prevents rebuilding identical images:

1. Software fingerprint = SHA256 of sorted enabled software keys
2. Cloud Function checks existing GCE images for matching `software-fingerprint` label
3. If match found + VM requested: skips build, creates VM from existing image
4. If match found + no VM: writes DUPLICATE status, done
5. If new combo: triggers full Packer build, labels image with fingerprint

---

## Testing

```bash
# Upload a test request
cat <<'EOF' > /tmp/test-request.json
{
  "submitter_name": "Test User",
  "submitter_email": "test@example.com",
  "ticket_number": "TEST-001",
  "request_type": "Cloud VM Provisioning",
  "workstation_size": "Medium",
  "software_packages": "Chrome, Git"
}
EOF

gsutil cp /tmp/test-request.json \
  gs://${PROJECT_ID}-image-builder-requests/requests/test-$(date +%s).json

# Check Cloud Function logs
gcloud functions logs read image-builder-process-request \
  --project=$PROJECT_ID --region=$REGION --limit=20

# Check Cloud Run Job execution
gcloud run jobs executions list --job=windows-image-builder \
  --project=$PROJECT_ID --region=$REGION --limit=3

# Check Cloud Run Job logs
gcloud logging read 'resource.type="cloud_run_job" AND resource.labels.job_name="windows-image-builder"' \
  --project=$PROJECT_ID --limit=30 --format="table(timestamp,textPayload)" --freshness=1h

# Check built images
gcloud compute images list --project=$PROJECT_ID \
  --filter="labels.built-by=image-builder"

# Check build status
gsutil cat gs://${PROJECT_ID}-image-builder-requests/status/REQUEST-ID.json
```

---

## Troubleshooting

| Issue | Fix |
|---|---|
| Packer WinRM timeout | Verify firewall allows TCP 5986 from `35.235.240.0/20` |
| Zone stockout error | Change zone in `cloud_run_job.tf` (e.g., `-b` to `-c`) |
| Email not sending | Ensure Cloud NAT exists on VPC for outbound SMTP access |
| Base image not found | Create Windows Server 2022 image with family `nmfs-windows-2022` |
| VM name conflict | VM names include request ID for uniqueness, should not repeat |
| Permission denied | Check service account roles (see Service Account Setup) |

---

## File Structure

```
windows-image-infra/
├── README.md                              # This file
├── cloudbuild-docker.yaml                 # Cloud Build: Packer builder Docker image
├── cloudbuild-win2022-customizer.yaml     # Cloud Build: Windows customizer
├── .gcloudignore                          # Files excluded from Cloud Build upload
├── terraform/                             # Infrastructure as Code
│   ├── provider.tf
│   ├── variables.tf                       # All configurable variables
│   ├── terraform.tfvars                   # Your environment values
│   ├── cloud_run_job.tf                   # Cloud Run Job + Scheduler
│   ├── eventarc.tf                        # GCS bucket, Eventarc trigger, Cloud Function
│   └── functions/
│       └── process-request/               # Cloud Function: normalize, dedup, trigger
│           ├── main.py
│           └── requirements.txt
└── win2022-oracle-client-dev/             # Packer Windows image builder
    ├── docker-entrypoint.sh               # Build orchestration (build + VM + user setup)
    └── packer/
        ├── customize.pkr.hcl              # Packer template
        ├── scripts/Dockerfile             # Builder container
        └── ansible-playbook/              # Software installation playbooks
            ├── main.yml
            └── install_*_tasks.yml        # Per-software install tasks
```
