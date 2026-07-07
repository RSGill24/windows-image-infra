# Windows Image Builder - Automated GCP Infrastructure

Automated Windows Server 2022 image builder triggered by Jira ticket creation.

## Architecture

```
Jira "Workstation Request" ticket
  |
  v
Jira Automation (webhook)
  |
  v
Cloud Run Service: jira-ingest-api
  |- Validates X-Jira-Secret header
  |- Writes raw JSON to GCS (jira-raw bucket)
  |- Transforms payload to image_config format
  '- Writes to request bucket -> triggers pipeline
        |
        v
Eventarc -> Cloud Function: process-request
  |- Auto-detects requester from Cloud Audit Logs
  |- Computes software fingerprint (SHA256)
  |- Checks for duplicate images
  |- DUPLICATE? -> Write status, skip build
  '- NEW? -> Trigger Cloud Run Job
        |
        v
Cloud Run Job: windows-image-builder
  |- Packer builds Windows VM with selected software
  |- Labels image with software fingerprint
  |- Creates VM from image (if requested)
  '- Writes build status to GCS

Eventarc -> Cloud Function: jira-processor
  '- Loads raw Jira data into BigQuery (analytics)
```

## Components

| Component | Type | Purpose |
|-----------|------|---------|
| `jira-ingest-api` | Cloud Run Service | Receives Jira webhooks, transforms payload |
| `process-request` | Cloud Function | Duplicate detection, triggers builds |
| `jira-processor` | Cloud Function | Loads Jira data into BigQuery |
| `windows-image-builder` | Cloud Run Job | Packer build + VM creation |
| `image-builder-requests` | GCS Bucket | Request/status/audit storage |
| `jira-raw` | GCS Bucket | Raw Jira webhook payloads |
| `jira_raw` / `jira_curated` | BigQuery | Jira analytics datasets |

## Image Naming

- **Image name**: `nmfs-windows-2022-{software}-{timestamp}`
  - Example: `nmfs-windows-2022-chrome-git-python-20260701123456`
- **Image family**: `nmfs-windows-2022`
- **VM name**: `{image-name}-vm`

## Supported Software (22 packages)

| Software | Key | Install Method |
|----------|-----|----------------|
| Google Chrome | `chrome` | Chocolatey |
| Git + GitHub Desktop | `git` | Chocolatey |
| Python | `python` | Chocolatey |
| JupyterLab | `jupyterlab` | pip |
| Miniconda | `conda` | Chocolatey |
| Anaconda | `anaconda` | Chocolatey |
| RStudio (OSS) | `rstudio` | Chocolatey |
| RStudio Pro | `rstudio_pro` | GCS binary |
| PyCharm Community | `pycharm_community` | Chocolatey |
| Visual Studio Community | `visual_studio_community` | Chocolatey |
| PowerShell 7+ | `powershell_core` | Chocolatey |
| Positron IDE | `positron` | GCS binary |
| ParaView | `paraview` | Chocolatey |
| Echoview | `echoview` | GCS binary |
| EchoSMs | `echosms` | GCS binary |
| EchoStack | `echostack` | GCS binary |
| MATLAB | `matlab` | GCS binary |
| NVIDIA GPU Drivers | `gpu_drivers` | GCS binary |
| Oracle Client | `oracle_client` | GCS binary |
| AA-SI aalibrary | `aalibrary` | GCS binary |
| GCP Utilities | `gcp_utilities` | gcloud SDK |
| Microsoft Excel | `excel` | Office Deployment Tool |

---

# Deployment Guide (Client Environment)

## Prerequisites

### 1. GCP Project Setup

```bash
# Set your project
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
  bigquery.googleapis.com \
  artifactregistry.googleapis.com \
  logging.googleapis.com \
  iam.googleapis.com \
  --project=$PROJECT_ID
```

### 3. VPC Network (must pre-exist)

The Packer builder requires:
- **Network**: `app-network`
- **Subnet**: `app-subnet1` (in the target region)
- **Firewall rule**: Allow WinRM (TCP 5986) from IAP range `35.235.240.0/20`

```bash
# Create firewall rule for Packer WinRM via IAP
gcloud compute firewall-rules create allow-winrm-iap \
  --network=app-network \
  --allow=tcp:5986 \
  --source-ranges=35.235.240.0/20 \
  --target-tags=winrm \
  --project=$PROJECT_ID
```

### 4. Phase 1 Base Image

A hardened Windows Server 2022 base image must exist in the project under family `nmfs-windows-2022`. This is the source image Packer customizes.

```bash
# Verify base image exists
gcloud compute images list --project=$PROJECT_ID --filter="family=nmfs-windows-2022"
```

### 5. Artifact Registry (Docker repo)

```bash
gcloud artifacts repositories create packer-images \
  --repository-format=docker \
  --location=$REGION \
  --project=$PROJECT_ID
```

### 6. Binary Software Bucket (for GCS-based installs)

Software like Oracle Client, MATLAB, Echoview, GPU drivers are installed from a GCS bucket. Create and upload binaries:

```bash
# Bucket name used in ansible playbooks
gsutil mb -l $REGION gs://org-sec-agents-bucket

# Upload binaries to appropriate paths:
# gs://org-sec-agents-bucket/oracle-client/instantclient-basic-windows.zip
# gs://org-sec-agents-bucket/matlab/matlab_installer.exe
# gs://org-sec-agents-bucket/echoview/Echoview_setup.exe
# gs://org-sec-agents-bucket/gpu-drivers/NVIDIA-vGPU-GRID.exe
# etc.
```

---

## Service Account Setup

### Create Service Account

```bash
gcloud iam service-accounts create packer-win-sa \
  --display-name="Packer Windows Image Builder SA" \
  --project=$PROJECT_ID
```

### Assign IAM Roles

The service account needs these roles:

```bash
SA_EMAIL="packer-win-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# Core roles
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
  "roles/bigquery.dataEditor"
  "roles/bigquery.jobUser"
  "roles/cloudfunctions.invoker"
)

for ROLE in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${ROLE}" \
    --condition=None
done
```

### Grant Eventarc Service Agent permissions

```bash
# Get project number
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# Eventarc service agent needs to invoke Cloud Run
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com" \
  --role="roles/eventarc.serviceAgent"

# Cloud Storage service agent needs to publish Eventarc events
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com" \
  --role="roles/pubsub.publisher"
```

---

## Secret Manager Setup

### 1. WinRM Password (required for Packer)

```bash
# Generate a strong password
WINRM_PW=$(openssl rand -base64 24)

gcloud secrets create packer-winrm-password \
  --project=$PROJECT_ID

echo -n "$WINRM_PW" | gcloud secrets versions add packer-winrm-password \
  --data-file=- --project=$PROJECT_ID
```

### 2. Jira Webhook Secret

```bash
# Generate a webhook secret
JIRA_SECRET=$(openssl rand -hex 32)

gcloud secrets create jira-webhook-secret \
  --project=$PROJECT_ID

echo -n "$JIRA_SECRET" | gcloud secrets versions add jira-webhook-secret \
  --data-file=- --project=$PROJECT_ID

# Save this value - you'll need it for Jira Automation configuration
echo "Jira webhook secret: $JIRA_SECRET"
```

---

## Configuration

### 1. Update terraform.tfvars

Edit `terraform/terraform.tfvars`:

```hcl
project_id               = "YOUR-PROJECT-ID"
region                   = "us-east4"
jira_raw_bucket_name     = "YOUR-PROJECT-ID-jira-raw"
jira_webhook_secret_name = "jira-webhook-secret"
```

### 2. Update provider.tf

Edit `terraform/provider.tf` - verify project and region match your tfvars.

### 3. Update cloudbuild-jira-ingest.yaml

Update substitutions:

```yaml
substitutions:
  _PROJECT_ID:  "YOUR-PROJECT-ID"
  _REGION:      "us-east4"
  _AR_REPO:     "packer-images"
  _IMAGE_NAME:  "jira-ingest-api"
```

---

## Deployment Steps

### Step 1: Authenticate

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project $PROJECT_ID
```

### Step 2: Build Docker Images

#### jira-ingest-api (webhook receiver):

```bash
cd windows-image-infra

gcloud builds submit \
  --config=cloudbuild-jira-ingest.yaml \
  --project=$PROJECT_ID \
  --region=$REGION
```

#### windows-packer-builder (Packer build image):

```bash
cat <<'CLOUDBUILD' | gcloud builds submit --config=/dev/stdin --project=$PROJECT_ID .
steps:
- name: 'gcr.io/cloud-builders/docker'
  args:
  - 'build'
  - '--no-cache'
  - '-t'
  - '${_REGION}-docker.pkg.dev/${_PROJECT_ID}/packer-images/windows-packer-builder:latest'
  - '-f'
  - 'win2022-oracle-client-dev/packer/scripts/Dockerfile'
  - '.'
substitutions:
  _PROJECT_ID: 'YOUR-PROJECT-ID'
  _REGION: 'us-east4'
images:
- '${_REGION}-docker.pkg.dev/${_PROJECT_ID}/packer-images/windows-packer-builder:latest'
options:
  logging: CLOUD_LOGGING_ONLY
CLOUDBUILD
```

### Step 3: Deploy Terraform

```bash
cd terraform

terraform init
terraform plan
terraform apply
```

**If resources already exist** (409 errors), import them:

```bash
# Example import commands (adjust names to your project):
terraform import google_storage_bucket.image_builder_requests $PROJECT_ID-image-builder-requests
terraform import google_storage_bucket.jira_raw YOUR-JIRA-RAW-BUCKET-NAME
terraform import google_cloud_run_v2_job.windows_image_builder projects/$PROJECT_ID/locations/$REGION/jobs/windows-image-builder
terraform import google_secret_manager_secret.jira_webhook_secret projects/$PROJECT_ID/secrets/jira-webhook-secret

# Then re-apply
terraform apply
```

### Step 4: Update Cloud Run Service

```bash
gcloud run services update jira-ingest-api \
  --image=$REGION-docker.pkg.dev/$PROJECT_ID/packer-images/jira-ingest-api:latest \
  --region=$REGION \
  --project=$PROJECT_ID
```

### Step 5: Update Cloud Run Job

```bash
DIGEST=$(gcloud artifacts docker images describe \
  $REGION-docker.pkg.dev/$PROJECT_ID/packer-images/windows-packer-builder:latest \
  --project=$PROJECT_ID --format="value(image_summary.digest)")

gcloud run jobs update windows-image-builder \
  --image="$REGION-docker.pkg.dev/$PROJECT_ID/packer-images/windows-packer-builder@${DIGEST}" \
  --region=$REGION \
  --project=$PROJECT_ID
```

### Step 6: Grant Cloud Run Invoker Permissions

```bash
SA_EMAIL="packer-win-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# process-request CF (triggered by Eventarc)
gcloud run services add-iam-policy-binding image-builder-process-request \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/run.invoker" \
  --region=$REGION --project=$PROJECT_ID

# jira-processor CF (triggered by Eventarc)
gcloud run services add-iam-policy-binding jira-processor \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/run.invoker" \
  --region=$REGION --project=$PROJECT_ID
```

### Step 7: Get Webhook URL

```bash
gcloud run services describe jira-ingest-api \
  --region=$REGION --project=$PROJECT_ID \
  --format="value(status.url)"
```

Output: `https://jira-ingest-api-XXXXXXXXX-XX.a.run.app`

Your webhook URL is: `https://jira-ingest-api-XXXXXXXXX-XX.a.run.app/webhook/jira`

---

## Jira Cloud Configuration

### 1. Create Custom Fields

Go to **Jira Settings > Fields** (global, not project-level) and create:

| Field Name | Field Type | Options |
|------------|-----------|---------|
| Software Selection | Checkboxes | Chrome, Git, Python, JupyterLab, Conda, Anaconda, RStudio, RStudio Pro, PyCharm Community, Visual Studio Community, PowerShell Core, Positron, ParaView, Echoview, EchoSMs, EchoStack, MATLAB, GPU Drivers, Oracle Client, AA Library, GCP Utilities, Excel |
| First Name | Short text | - |
| Group Name | Short text | - |
| Approver Name | Short text | - |

### 2. Create Work Type

1. Go to **Project Settings > Work types**
2. Add **"Workstation Request"** work type
3. Add it to the **Default work type scheme**

### 3. Add Fields to Work Type Layout

1. Go to **Project Settings > Work types > Workstation Request**
2. In the right "Fields" panel, search and drag in:
   - Software Selection
   - First Name
   - Group Name
   - Approver Name
3. Click **Save changes**

> If fields don't appear in search, go to **Project Settings > Fields** first and click **Add field** to add your global fields to the space.

### 4. Create Automation Rule

1. Go to **Project Settings > Automation**
2. Create new rule:
   - **Trigger**: Work item created
   - **Condition**: Issue type = Workstation Request
   - **Action**: Send web request

Configure the web request:

| Setting | Value |
|---------|-------|
| URL | `https://YOUR-CLOUD-RUN-URL/webhook/jira` |
| Method | POST |
| Body | Custom data (see below) |
| Headers | `X-Jira-Secret: YOUR-JIRA-WEBHOOK-SECRET` |

**Request Body:**

```json
{
  "event": "jira_workstation_request",
  "eventType": "issue_created",
  "sourceSystem": "jira",
  "ticket_id": "{{issue.key}}",
  "issueKey": "{{issue.key}}",
  "projectKey": "{{issue.project.key}}",
  "status": "{{issue.status.name}}",
  "summary": "{{issue.summary}}",
  "created": "{{issue.created}}",
  "updated": "{{issue.updated}}",
  "reporter_email": "{{issue.reporter.emailAddress}}",
  "reporter_display_name": "{{issue.reporter.displayName}}",
  "first_name": "{{issue.First Name}}",
  "group_name": "{{issue.Group Name}}",
  "approvers": "{{issue.Approver Name}}",
  "software_selections": "{{issue.Software Selection}}"
}
```

> Replace `{{issue.First Name}}` etc. with actual smart values from your Jira fields.

### 5. Enable the Rule

Toggle the rule **ON** and save.

---

## Testing

### End-to-End Test

1. Create a **Workstation Request** ticket in Jira
2. Fill in: Summary, First Name, Group Name, Approver Name, Software Selection (pick 2-3)
3. Submit

### Verify Pipeline

```bash
# Check Jira Automation audit log (in Jira UI)
# Should show: "Successfully published web request"

# Check raw payload stored
gcloud storage ls "gs://YOUR-JIRA-RAW-BUCKET/jira/raw/" --project=$PROJECT_ID --recursive

# Check request file created
gcloud storage ls "gs://${PROJECT_ID}-image-builder-requests/requests/" --project=$PROJECT_ID

# Check Cloud Run job execution
gcloud run jobs executions list --job=windows-image-builder \
  --project=$PROJECT_ID --region=$REGION --limit=3

# Check build status
gcloud storage cat "gs://${PROJECT_ID}-image-builder-requests/status/REQUEST-ID.json" \
  --project=$PROJECT_ID

# Check built images
gcloud compute images list --project=$PROJECT_ID --filter="family=nmfs-windows-2022"

# Check Cloud Run logs
gcloud logging read 'resource.type="cloud_run_job" AND resource.labels.job_name="windows-image-builder"' \
  --project=$PROJECT_ID --limit=30 --format="table(timestamp,textPayload)" --freshness=1h
```

---

## GCS Bucket Structure

```
gs://{PROJECT_ID}-image-builder-requests/
  requests/          # Input: JSON request files (trigger Eventarc)
  processed/         # Enriched JSON passed to Cloud Run job
  audit/             # Permanent audit trail (who, what, when)
  status/            # Build status per request ID

gs://{JIRA_RAW_BUCKET}/
  jira/raw/
    project_key={KEY}/
      date={YYYY-MM-DD}/
        issue-{KEY}-{N}.json   # Raw Jira webhook payloads
```

## BigQuery Datasets

| Dataset | Table | Purpose |
|---------|-------|---------|
| `jira_raw` | `issue_events` | Raw event log (append-only, partitioned by day) |
| `jira_curated` | `issue_current` | Current state of each Jira issue (upsert) |
| `jira_curated` | `issue_history` | Status change history (append-only) |

---

## Duplicate Detection

The system prevents rebuilding identical images:

1. **Software fingerprint** = SHA256 of sorted enabled software keys (first 16 chars)
2. `process-request` CF checks existing GCE images for matching `software-fingerprint` label
3. If match found: writes DUPLICATE status, skips build
4. If new: triggers Cloud Run job which labels the built image with the fingerprint

---

## Troubleshooting

### Jira webhook returns 401
- Verify `X-Jira-Secret` header value matches the secret in Secret Manager
- Check: `gcloud secrets versions access latest --secret=jira-webhook-secret --project=$PROJECT_ID`

### Jira webhook returns 400
- Check Cloud Run logs: `gcloud logging read 'resource.labels.service_name="jira-ingest-api"' --project=$PROJECT_ID --limit=10`
- Common cause: Software Selection field name mismatch in webhook body

### Eventarc trigger not firing
- Verify trigger exists: `gcloud eventarc triggers list --project=$PROJECT_ID --location=$REGION`
- Check service account has `roles/run.invoker` on target service
- Check `roles/eventarc.eventReceiver` on service account

### Cloud Run job fails with permission denied
- `run.jobs.run` denied: Grant `roles/run.developer` to service account
- `compute.*` denied: Grant `roles/compute.admin` to service account

### Packer build fails - WinRM timeout
- Verify firewall rule allows TCP 5986 from `35.235.240.0/20` with tag `winrm`
- Verify IAP API is enabled
- Check base image exists in family `nmfs-windows-2022`

### Image already exists error
- Packer image names must be unique. The timestamp in the name prevents this.
- If it happens, delete the old image: `gcloud compute images delete IMAGE-NAME --project=$PROJECT_ID`

---

## File Structure

```
windows-image-infra/
├── README.md                              # This file
├── cloudbuild-jira-ingest.yaml            # Cloud Build: jira-ingest-api Docker image
├── sample-request.json                    # Example request JSON
├── jira-ingest-api/                       # Cloud Run Service: webhook receiver
│   ├── Dockerfile
│   ├── main.py                            # FastAPI app (POST /webhook/jira)
│   ├── transform.py                       # Jira payload -> image_config converter
│   └── requirements.txt
├── terraform/                             # Infrastructure as Code
│   ├── provider.tf                        # Google provider config
│   ├── variables.tf                       # All configurable variables
│   ├── terraform.tfvars                   # Environment-specific values
│   ├── cloud_run_job.tf                   # Cloud Run Job: windows-image-builder
│   ├── eventarc.tf                        # GCS bucket, Eventarc trigger, process-request CF
│   ├── jira.tf                            # Jira integration (BigQuery, raw bucket, IAM)
│   └── functions/
│       ├── process-request/               # CF: duplicate detection + build trigger
│       │   ├── main.py
│       │   └── requirements.txt
│       └── jira-processor/                # CF: Jira data -> BigQuery
│           ├── main.py
│           └── requirements.txt
└── win2022-oracle-client-dev/             # Packer Windows image builder
    ├── docker-entrypoint.sh               # Main build orchestration script
    └── packer/
        ├── customize.pkr.hcl              # Packer template (HCL)
        ├── scripts/Dockerfile             # Builder container image
        └── ansible-playbook/              # Software installation playbooks
            ├── main.yml
            └── roles/                     # 22 software installation roles
```
SSM trigger test - Tue Jul  7 12:27:53 IST 2026
SSM trigger test 3 - Tue Jul  7 12:29:38 IST 2026
SSM trigger test after fix - Tue Jul  7 12:33:51 IST 2026
