# Windows Image Builder - Client Deployment Guide

Automated GCP pipeline that builds customized Windows Server 2022 images with selectable software packages. Users submit a **Jira Workstation Request**, and the system automatically builds the image, tracks metadata, detects duplicates, loads analytics into BigQuery, and notifies the requester via email.

---

## Architecture Overview

### Primary Flow: Jira → GCP (Recommended)

```
User submits "Workstation Request" in Jira portal
        |
        v
  Jira Automation rule fires (Issue Created)
        |
        v
  HTTP POST webhook to Cloud Run (jira-ingest-api)
        |
        +---> Validates X-Jira-Secret header
        +---> Writes RAW JSON to gs://nmfs-winde-jira-raw-dev/jira/raw/...
        +---> Transforms Jira payload → image_config format
        +---> Writes to gs://{project}-image-builder-requests/requests/jira-{issueKey}.json
        |            |
        |            v
        |     Eventarc trigger (existing)
        |            |
        |            v
        |     Cloud Function: process-request (existing)
        |            |
        |            +---> Duplicate? --> Notify user, skip build
        |            |
        |            +---> New? --> Cloud Run Job (Packer + Ansible)
        |                               |
        |                               v
        |                       Build Windows Image
        |                               |
        |                               +---> Label image with fingerprint
        |                               +---> Create VM (optional)
        |                               +---> Pub/Sub notification
        |                               +---> Cloud Function: notify-email --> SendGrid
        |
        +---> Eventarc trigger on raw bucket (new)
                     |
                     v
              Cloud Function: jira-processor (new)
                     |
                     +---> BigQuery: jira_raw.issue_events
                     +---> BigQuery: jira_curated.issue_current
                     +---> BigQuery: jira_curated.issue_history
                     |
                     v
              Looker / Reporting / Dashboards
```

### Legacy Flow: Direct GCS Upload (Still Supported)

```
User uploads JSON to GCS (/requests/)
        |
        v
  Eventarc trigger → process-request CF → Cloud Run Job → notify-email
```

> The direct GCS upload path still works unchanged. Jira integration is an additional entry point that feeds into the same pipeline.

---

### Components

| Component | Type | Status | Purpose |
|-----------|------|--------|---------|
| **jira-ingest-api** | Cloud Run Service | **NEW** | Receives Jira webhooks, validates, transforms, writes to GCS |
| **jira-processor** | Cloud Function | **NEW** | Loads raw Jira data into BigQuery |
| **nmfs-winde-jira-raw-dev** | GCS Bucket | **NEW** | Stores raw Jira webhook payloads |
| **jira_raw / jira_curated** | BigQuery Datasets | **NEW** | Analytics & reporting tables |
| **jira-webhook-secret** | Secret Manager | **NEW** | Shared secret for Jira → Cloud Run auth |
| **jira-ingest-sa** | Service Account | **NEW** | SA for jira-ingest-api |
| **jira-processor-sa** | Service Account | **NEW** | SA for jira-processor |
| **GCS Bucket** | GCS | Existing | Request intake, audit trail, status tracking |
| **Eventarc** | Trigger | Existing | Triggers processing on file upload |
| **process-request** | Cloud Function | Existing | Pre-processor: dedup, audit, trigger build |
| **Cloud Run Job** | Job | Existing | Packer + Ansible Windows image builder |
| **notify-email** | Cloud Function | Existing | Email via SendGrid on completion |
| **Pub/Sub** | Topic | Existing | Notification delivery |
| **Cloud Scheduler** | Scheduler | Existing | Optional scheduled builds (ENV mode) |
| **Cloud Build** | CI/CD | Existing + NEW | Docker builder image + jira-ingest-api image |

---

## Prerequisites

### 1. GCP APIs to Enable

```bash
gcloud services enable \
  compute.googleapis.com \
  run.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  cloudscheduler.googleapis.com \
  eventarc.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  logging.googleapis.com \
  pubsub.googleapis.com \
  iap.googleapis.com \
  bigquery.googleapis.com \
  --project=<YOUR_PROJECT_ID>
```

<!-- CHANGE: Added bigquery.googleapis.com for Jira analytics -->

### 2. VPC Network & Subnet

A VPC network and subnet must exist before deployment. The Cloud Run job and Packer build VMs run inside this network.

| Resource | Default Name | Notes |
|----------|-------------|-------|
| Network | `app-network` | Must exist before `terraform apply` |
| Subnet | `app-subnet1` | Must have enough free IPs (use `/16` or larger) |

> **Where to change:** `terraform/cloud_run_job.tf` lines 28-29 (network_interfaces block)

### 3. Base (Hardened) Image

Phase 1 must have produced a hardened Windows Server 2022 image family. This is the **source image** that Phase 2 customizes.

| Variable | Default Value | Where to Change |
|----------|--------------|-----------------|
| `SOURCE_IMAGE_FAMILY` | `nmfs-windows-2022` | `terraform/cloud_run_job.tf` line 56 |
| `SOURCE_IMAGE_PROJECT_ID` | Same as `PROJECT_ID` | `terraform/cloud_run_job.tf` line 51 |

> If the hardened image is in a **different GCP project**, update `SOURCE_IMAGE_PROJECT_ID` accordingly.

### 4. Artifact Registry Repository

Create a Docker repository for builder images:

```bash
gcloud artifacts repositories create packer-images \
  --repository-format=docker \
  --location=<REGION> \
  --project=<YOUR_PROJECT_ID>
```

<!-- CHANGE: This repo now holds TWO images: windows-packer-software AND jira-ingest-api -->

---

## Service Account & IAM Permissions

All components use a **single shared service account**: `packer-win-sa`

### `packer-win-sa` (Manual Setup)

**Used by:** Cloud Run Job, Cloud Build, Cloud Functions, Jira Ingest API, Jira Processor, Eventarc triggers — everything.

```bash
gcloud iam service-accounts create packer-win-sa \
  --display-name="Packer Windows Image Builder" \
  --project=<YOUR_PROJECT_ID>
```

**Required IAM Roles:**

```bash
PROJECT_ID=<YOUR_PROJECT_ID>
SA=packer-win-sa@${PROJECT_ID}.iam.gserviceaccount.com

# Compute (Packer builds, image management, VM creation)
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/compute.instanceAdmin.v1"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/compute.imageAdmin"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/compute.networkAdmin"

# Storage (GCS buckets: requests, raw Jira, binaries)
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/storage.admin"

# Secrets (WinRM password, SendGrid key, Jira webhook secret)
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/secretmanager.secretAccessor"

# Artifact Registry (push Docker images)
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/artifactregistry.writer"

# Pub/Sub (build notifications)
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/pubsub.publisher"

# Logging (audit log queries, uploader detection)
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/logging.logWriter"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/logging.viewer"

# IAM & IAP (service account impersonation, private VM access)
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/iam.serviceAccountUser"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/iap.tunnelResourceAccessor"

# Cloud Build (Docker image builds)
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/cloudbuild.builds.builder"

# Cloud Run (trigger jobs, invoke services)
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/run.invoker"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/run.developer"

# Eventarc (receive GCS file events)
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/eventarc.eventReceiver"

# BigQuery (Jira analytics — NEW)
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/bigquery.dataEditor"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA" --role="roles/bigquery.jobUser"
```

> **Where referenced:** Every Terraform resource, Cloud Build YAML, and Cloud Run config uses `packer-win-sa@{PROJECT_ID}.iam.gserviceaccount.com`

---

## Secret Manager Setup

Three secrets must be created before deployment:

### 1. WinRM Password (Existing)

```bash
PASSWORD=$(openssl rand -base64 24)

gcloud secrets create packer-winrm-password \
  --project=<YOUR_PROJECT_ID>

echo -n "$PASSWORD" | gcloud secrets versions add packer-winrm-password \
  --data-file=- --project=<YOUR_PROJECT_ID>
```

> **Where referenced:** `terraform/cloud_run_job.tf` line 90 (`WINRM_SECRET` env var)

### 2. SendGrid API Key (Existing)

```bash
gcloud secrets create sendgrid-api-key \
  --project=<YOUR_PROJECT_ID>

echo -n "SG.your-sendgrid-api-key-here" | gcloud secrets versions add sendgrid-api-key \
  --data-file=- --project=<YOUR_PROJECT_ID>
```

> **Where referenced:** `terraform/variables.tf` (`sendgrid_api_key_secret`), `terraform/eventarc.tf` line 273

### 3. Jira Webhook Secret — NEW

```bash
# Generate a strong random secret
JIRA_SECRET=$(openssl rand -base64 32)
echo "Save this for Jira Automation config: $JIRA_SECRET"

gcloud secrets create jira-webhook-secret \
  --project=<YOUR_PROJECT_ID>

echo -n "$JIRA_SECRET" | gcloud secrets versions add jira-webhook-secret \
  --data-file=- --project=<YOUR_PROJECT_ID>
```

<!-- CHANGE: This secret value must also be configured in Jira Automation rule as the X-Jira-Secret header -->

> **Where referenced:** `terraform/jira.tf` (Secret Manager resource), `jira-ingest-api/main.py` (validates header)
>
> **IMPORTANT:** Copy this secret value — you will need it when configuring the Jira Automation rule (Step 6).

---

## Configuration: What to Change for Your Environment

### File: `terraform/variables.tf`

| Variable | What to Set | Example |
|----------|------------|---------|
| `project_id` | Your GCP Project ID | `my-org-project-123` |
| `region` | GCP region | `us-east4` |
| `sendgrid_api_key_secret` | Secret Manager secret name | `sendgrid-api-key` |
| `notification_from_email` | Sender email for notifications | `imagebuilder@yourorg.com` |
| `jira_raw_bucket_name` | Bucket for raw Jira payloads | `nmfs-winde-jira-raw-dev` |
| `jira_webhook_secret_name` | Secret name for webhook auth | `jira-webhook-secret` |

<!-- CHANGE: Update jira_raw_bucket_name if you want a different bucket name -->
<!-- CHANGE: Update jira_webhook_secret_name if you use a different secret name -->

### File: `terraform/cloud_run_job.tf`

| Line | Variable | What to Change |
|------|----------|---------------|
| 21 | `service_account` | Update if SA name differs from `packer-win-sa` |
| 28 | `network` | Your VPC network name |
| 29 | `subnetwork` | Your subnet name (must have free IPs) |
| 36 | `image` | Only if Artifact Registry repo name differs |
| 56 | `SOURCE_IMAGE_FAMILY` | Your Phase 1 hardened image family |
| 60 | `IMAGE_FAMILY` | Output image family name |
| 68 | `MACHINE_TYPE` | Build VM size (default: `e2-standard-8`) |
| 72 | `SERVICE_ACCOUNT_EMAIL` | Must match SA used for Packer |

### File: `terraform/jira.tf` — NEW

| Resource | What to Change |
|----------|---------------|
| `google_cloud_run_v2_service.jira_ingest_api` | Image path if AR repo differs |
| `google_cloud_run_v2_service_iam_member.jira_ingest_public` | Change `allUsers` to specific SA if Jira can authenticate via Google IAM |
| `google_storage_bucket.jira_raw` | Bucket name, location, lifecycle rules |
| BigQuery datasets | Location must match your region |

<!-- CHANGE: If your org policy blocks allUsers on Cloud Run, you'll need to set up
     a Jira-side GCP service account or use a different auth method. See the
     "Jira Cloud Configuration" section below for alternatives. -->

### File: `cloudbuild-win2022-customizer.yaml` (Existing)

| Line | Variable | What to Change |
|------|----------|---------------|
| 2 | `_PROJECT_ID` | Your GCP Project ID |
| 3 | `_SOURCE_IMAGE_PROJECT_ID` | Project containing Phase 1 image |
| 4 | `_SOURCE_IMAGE_FAMILY` | Phase 1 hardened image family |
| 5 | `_ZONE` | Build zone |
| 13 | `_REGION` | Your region |
| 59 | `serviceAccount` | Your Packer SA email |

### File: `cloudbuild-jira-ingest.yaml` — NEW

| Line | Variable | What to Change |
|------|----------|---------------|
| 2 | `_PROJECT_ID` | Your GCP Project ID |
| 3 | `_REGION` | Your region |
| 4 | `_AR_REPO` | Artifact Registry repo name (default: `packer-images`) |

### File: `jira-ingest-api/transform.py` — NEW

| Section | What to Change |
|---------|---------------|
| `VALID_SOFTWARE_KEYS` | Add/remove software keys if your playbook set changes |
| `transform_jira_to_image_config()` | Update image_name pattern if naming convention differs |
| `extract_software()` | Update field locations if Jira form nests software differently |

<!-- CHANGE: When the final Jira ProForma form is ready, update extract_software()
     to match where software selections appear in the actual payload.
     Current code checks: payload["software"], payload["image_config"]["software"],
     and individual install_* fields. -->

---

## Deployment Steps

### Step 1: Clone the Repository

```bash
git clone <REPO_URL> windows-image-infra
cd windows-image-infra
```

### Step 2: Create Secrets

```bash
PROJECT_ID=<YOUR_PROJECT_ID>

# WinRM password
PASSWORD=$(openssl rand -base64 24)
gcloud secrets create packer-winrm-password --project=$PROJECT_ID
echo -n "$PASSWORD" | gcloud secrets versions add packer-winrm-password --data-file=- --project=$PROJECT_ID

# SendGrid API key
gcloud secrets create sendgrid-api-key --project=$PROJECT_ID
echo -n "SG.your-key-here" | gcloud secrets versions add sendgrid-api-key --data-file=- --project=$PROJECT_ID

# Jira webhook secret (NEW)
JIRA_SECRET=$(openssl rand -base64 32)
echo ">>> SAVE THIS for Jira config: $JIRA_SECRET"
gcloud secrets create jira-webhook-secret --project=$PROJECT_ID
echo -n "$JIRA_SECRET" | gcloud secrets versions add jira-webhook-secret --data-file=- --project=$PROJECT_ID
```

### Step 3: Create Terraform Variables File

```bash
cat > terraform/terraform.tfvars << 'EOF'
project_id              = "YOUR-PROJECT-ID"
region                  = "us-east4"
notification_from_email = "imagebuilder@yourorg.com"
sendgrid_api_key_secret = "sendgrid-api-key"

# Jira integration (NEW)
jira_raw_bucket_name     = "nmfs-winde-jira-raw-dev"
jira_webhook_secret_name = "jira-webhook-secret"

# Default software selection (for scheduled builds / ENV mode)
install_chrome       = false
install_git          = false
install_python       = false
install_oracle       = false
install_rstudio      = false
install_conda        = false
install_jupyterlab   = false
install_powershell_core = false
install_pycharm      = false
install_visual_studio = false
install_paraview     = false
install_echoview     = false
install_matlab       = false
install_rstudio_pro  = false
install_positron     = false
install_anaconda     = false
install_gpu_drivers  = false
install_aalibrary    = false
install_echosms      = false
install_echostack    = false
install_gcp_utilities = false
install_excel        = false
EOF
```

### Step 4: Build and Push Docker Images

```bash
# Image 1: Packer builder (existing)
gcloud builds submit \
  --config=cloudbuild-win2022-customizer.yaml \
  --region=us-east4 .

# Image 2: Jira ingest API (NEW)
gcloud builds submit \
  --config=cloudbuild-jira-ingest.yaml \
  --region=us-east4 .
```

<!-- CHANGE: If you changed _PROJECT_ID, _REGION, or _AR_REPO in the YAML files,
     pass them as substitutions:
     --substitutions=_PROJECT_ID=your-project,_REGION=your-region -->

### Step 5: Deploy Infrastructure with Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This creates:

**Existing resources:**
- GCS request bucket (`{PROJECT_ID}-image-builder-requests`)
- Pub/Sub topic (`image-builder-notifications`)
- Cloud Function: `image-builder-process-request`
- Cloud Function: `image-builder-notify-email`
- Eventarc trigger on GCS uploads
- Cloud Run Job: `windows-image-builder`
- Cloud Scheduler job (weekly builds)

**NEW resources (Jira integration):**
- Cloud Run Service: `jira-ingest-api`
- Cloud Function: `jira-processor`
- GCS Bucket: `nmfs-winde-jira-raw-dev`
- BigQuery datasets: `jira_raw`, `jira_curated`
- BigQuery tables: `issue_events`, `issue_current`, `issue_history`
- Eventarc trigger: Jira raw bucket → jira-processor
- Secret Manager: `jira-webhook-secret`
- Service accounts: `jira-ingest-sa`, `jira-processor-sa`, `eventarc-jira-trigger`

### Step 6: Configure Jira Cloud

After Terraform apply, get the Cloud Run URL:

```bash
terraform output jira_ingest_api_url
# Example: https://jira-ingest-api-abc123-ue.a.run.app
```

Now configure Jira:

#### 6a. Create Custom Fields in Jira

Go to **Jira Admin → Custom Fields** and create:

| Field Name | Field Type | Purpose |
|---|---|---|
| `first_name` | Short Text | Requester's first name |
| `group_name` | Short Text or Select List | Team (GARFO, etc.) |
| `approvers` | Short Text or User Picker | Approver |
| 22x software fields | Checkbox (true/false) | One per software option |

<!-- CHANGE: The actual custom field IDs (customfield_10050, etc.) will be different
     in your Jira instance. Use the Jira REST API to find them:
     GET https://your-org.atlassian.net/rest/api/3/field
     Then update the Jira Automation body template with correct field IDs. -->

**Alternative:** Instead of 22 separate checkboxes, use a single **Multi-Select** field named "Software" with all options. Then in the Automation body template, map selections to the `software` dict.

#### 6b. Create Request Type in Jira Service Management

1. Go to **Project Settings → Request Types**
2. Create: "Workstation Request"
3. Add the custom fields to the form
4. Publish to the customer portal

#### 6c. Create Automation Rule

Go to **Project Settings → Automation → Create Rule**:

```
Rule name:  "Trigger GCP Image Build"

TRIGGER:    Issue Created
            Filter: issue type = "Workstation Request"

ACTION:     Send Web Request
            URL:     https://jira-ingest-api-XXXXX-ue.a.run.app/webhook/jira
            Method:  POST
            Headers:
              Content-Type: application/json
              X-Jira-Secret: <paste-secret-from-step-2>
            Body:    Custom data (JSON)
```

<!-- CHANGE: Replace the URL with your actual Cloud Run URL from terraform output -->
<!-- CHANGE: Replace <paste-secret-from-step-2> with the JIRA_SECRET value you saved -->

**Body template (JSON) using Jira smart values:**

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
  "first_name": "{{issue.customfield_XXXXX}}",
  "group_name": "{{issue.customfield_XXXXX}}",
  "approvers": "{{issue.customfield_XXXXX}}",
  "software": {
    "chrome": {{issue.customfield_XXXXX}},
    "git": {{issue.customfield_XXXXX}},
    "python": {{issue.customfield_XXXXX}},
    "jupyterlab": {{issue.customfield_XXXXX}},
    "conda": {{issue.customfield_XXXXX}},
    "anaconda": {{issue.customfield_XXXXX}},
    "rstudio": {{issue.customfield_XXXXX}},
    "rstudio_pro": {{issue.customfield_XXXXX}},
    "pycharm_community": {{issue.customfield_XXXXX}},
    "visual_studio_community": {{issue.customfield_XXXXX}},
    "powershell_core": {{issue.customfield_XXXXX}},
    "positron": {{issue.customfield_XXXXX}},
    "paraview": {{issue.customfield_XXXXX}},
    "echoview": {{issue.customfield_XXXXX}},
    "echosms": {{issue.customfield_XXXXX}},
    "echostack": {{issue.customfield_XXXXX}},
    "matlab": {{issue.customfield_XXXXX}},
    "gpu_drivers": {{issue.customfield_XXXXX}},
    "oracle_client": {{issue.customfield_XXXXX}},
    "aalibrary": {{issue.customfield_XXXXX}},
    "gcp_utilities": {{issue.customfield_XXXXX}},
    "excel": {{issue.customfield_XXXXX}}
  }
}
```

<!-- CHANGE: Replace every customfield_XXXXX with the actual field ID from your Jira instance.
     Find field IDs: GET https://your-org.atlassian.net/rest/api/3/field
     Or go to Jira Admin > Custom Fields > click field > ID is in the URL. -->

### Step 7: Verify Deployment

```bash
# Check Cloud Run service (Jira ingest API - NEW)
gcloud run services describe jira-ingest-api \
  --region=<REGION> --project=<PROJECT_ID>

# Check Cloud Run job (existing)
gcloud run jobs describe windows-image-builder \
  --region=<REGION> --project=<PROJECT_ID>

# Check Cloud Functions (existing + new)
gcloud functions list --project=<PROJECT_ID> --region=<REGION>

# Check Eventarc triggers (existing + new)
gcloud eventarc triggers list --location=<REGION> --project=<PROJECT_ID>

# Check BigQuery datasets (NEW)
bq ls --project_id=<PROJECT_ID>

# Check GCS buckets
gsutil ls gs://<PROJECT_ID>-image-builder-requests/
gsutil ls gs://nmfs-winde-jira-raw-dev/

# Health check the Jira API (NEW)
curl https://$(terraform output -raw jira_ingest_api_url)/health
```

### Step 8: End-to-End Test

```bash
# Send a mock Jira webhook (simulates what Jira Automation sends)
JIRA_URL=$(cd terraform && terraform output -raw jira_ingest_api_url)

curl -X POST "${JIRA_URL}/webhook/jira" \
  -H "Content-Type: application/json" \
  -H "X-Jira-Secret: <your-jira-secret>" \
  -d '{
    "event": "jira_workstation_request",
    "eventType": "issue_created",
    "sourceSystem": "jira",
    "ticket_id": "NOAA-TEST-1",
    "issueKey": "NOAA-TEST-1",
    "projectKey": "NOAA",
    "status": "Submitted",
    "summary": "Test workstation request",
    "reporter_email": "test@example.com",
    "first_name": "Test",
    "group_name": "GARFO",
    "approvers": "Test",
    "software": {
      "chrome": true,
      "git": true,
      "python": true,
      "gcp_utilities": true
    }
  }'

# Verify raw payload landed
gsutil ls gs://nmfs-winde-jira-raw-dev/jira/raw/project_key=NOAA/

# Verify transformed request landed (triggers existing pipeline)
gsutil ls gs://<PROJECT_ID>-image-builder-requests/requests/jira-NOAA-TEST-1*

# Check BigQuery
bq query --use_legacy_sql=false \
  'SELECT event_id, issue_key, event_type, ingested_at FROM jira_raw.issue_events ORDER BY ingested_at DESC LIMIT 5'

# Check process-request Cloud Function logs
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="image-builder-process-request"' \
  --project=<PROJECT_ID> --limit=10 --freshness=15m \
  --format="table(timestamp,textPayload)"
```

---

## Jira-to-Image Flow: Step-by-Step Detail

Here's exactly what happens when a user submits a Jira ticket:

| Step | What Happens | File/Service | Output |
|------|-------------|-------------|--------|
| 1 | User fills "Workstation Request" form in Jira portal | Jira UI | Ticket NOAA-5 created |
| 2 | Jira Automation detects "Issue Created" event | Jira Automation Rule | HTTP POST fires |
| 3 | POST hits `/webhook/jira` on Cloud Run | `jira-ingest-api/main.py` | Payload received |
| 4 | Validates `X-Jira-Secret` header | `jira-ingest-api/main.py` | 401 if invalid |
| 5 | Validates required fields (ticket_id, event) | `jira-ingest-api/main.py` | 400 if missing |
| 6 | Writes raw JSON to GCS | `jira-ingest-api/main.py` | `gs://nmfs-winde-jira-raw-dev/jira/raw/...` |
| 7 | Transforms Jira payload → image_config format | `jira-ingest-api/transform.py` | JSON with `image_config.software` dict |
| 8 | Writes transformed JSON to request bucket | `jira-ingest-api/main.py` | `gs://{project}-...-requests/requests/jira-NOAA-5-*.json` |
| 9 | Returns 200 to Jira | `jira-ingest-api/main.py` | Jira Automation sees success |
| 10 | Eventarc detects new file in raw bucket | Eventarc trigger (new) | Fires jira-processor CF |
| 11 | Loads raw data into BigQuery | `terraform/functions/jira-processor/main.py` | BQ tables populated |
| 12 | Eventarc detects new file in request bucket | Eventarc trigger (existing) | Fires process-request CF |
| 13 | process-request reads JSON, skips auto-detect (requester pre-populated) | `terraform/functions/process-request/main.py` | Requester = "Steven" |
| 14 | Computes software fingerprint | `terraform/functions/process-request/main.py` | SHA256 hash |
| 15 | Checks for duplicate image | `terraform/functions/process-request/main.py` | Match or no match |
| 16a | **If duplicate:** writes status, sends notification | process-request + notify-email | Email: "Image already exists" |
| 16b | **If new:** triggers Cloud Run Job | process-request → Cloud Run Job | Packer build starts |
| 17 | Packer + Ansible builds Windows image | `docker-entrypoint.sh` | GCP image created |
| 18 | Labels image, optionally creates VM | `docker-entrypoint.sh` | VM running (if requested) |
| 19 | Publishes to Pub/Sub | `docker-entrypoint.sh` | Notification message |
| 20 | notify-email sends email via SendGrid | `terraform/functions/notify-email/main.py` | "Your image is ready!" |

---

## Usage: Submitting a Build Request

### Method 1: Jira Ticket (Recommended)

1. Go to your Jira Service Management portal
2. Select "Workstation Request"
3. Fill in your name, team, and check the software you need
4. Click **Submit**
5. You'll receive an email when the build completes (or if a matching image already exists)

### Method 2: Direct GCS Upload (Legacy)

```json
{
  "image_config": {
    "image_name": "",
    "create_vm": false,
    "keep_image": true,
    "software": {
      "chrome": true,
      "git": true,
      "python": true,
      "jupyterlab": false,
      "conda": false,
      "anaconda": false,
      "rstudio": false,
      "rstudio_pro": false,
      "pycharm_community": false,
      "visual_studio_community": false,
      "powershell_core": true,
      "positron": false,
      "paraview": false,
      "echoview": false,
      "echosms": false,
      "echostack": false,
      "matlab": false,
      "gpu_drivers": false,
      "oracle_client": false,
      "aalibrary": false,
      "gcp_utilities": true,
      "excel": false
    }
  }
}
```

```bash
gsutil cp my-request.json gs://<PROJECT_ID>-image-builder-requests/requests/my-request.json
```

### Monitoring a Build

```bash
# Process-request Cloud Function logs
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="image-builder-process-request"' \
  --project=<PROJECT_ID> --limit=20 --freshness=15m \
  --format="table(timestamp,textPayload)"

# Cloud Run job logs (Packer build)
gcloud logging read \
  'resource.type="cloud_run_job" AND resource.labels.job_name="windows-image-builder"' \
  --project=<PROJECT_ID> --limit=30 --freshness=1h \
  --format="table(timestamp,textPayload)"

# Jira ingest API logs (NEW)
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="jira-ingest-api"' \
  --project=<PROJECT_ID> --limit=20 --freshness=15m \
  --format="table(timestamp,textPayload)"

# Build status in GCS
gsutil cat gs://<PROJECT_ID>-image-builder-requests/status/<REQUEST_ID>.json

# BigQuery: Jira ticket status (NEW)
bq query --use_legacy_sql=false \
  'SELECT issue_key, status, reporter_email, last_synced_at FROM jira_curated.issue_current ORDER BY last_synced_at DESC LIMIT 10'
```

---

## GCS Bucket Structure

### Request Bucket (Existing): `{PROJECT_ID}-image-builder-requests`

```
gs://<PROJECT_ID>-image-builder-requests/
  |-- requests/      # JSON files (from Jira or direct upload)
  |-- processed/     # Enriched JSON with metadata (auto-created)
  |-- audit/         # Permanent audit trail per request (auto-created)
  +-- status/        # Build status per request ID (auto-created)
```

### Jira Raw Bucket (NEW): `nmfs-winde-jira-raw-dev`

```
gs://nmfs-winde-jira-raw-dev/
  +-- jira/raw/
        +-- project_key=NOAA/
              +-- date=2026-06-29/
                    |-- issue-NOAA-4.json
                    +-- issue-NOAA-5.json
```

### BigQuery Tables (NEW)

| Table | Dataset | Purpose | Type |
|-------|---------|---------|------|
| `issue_events` | `jira_raw` | Every Jira webhook event | Append-only, partitioned by `ingested_at` |
| `issue_current` | `jira_curated` | Latest state per Jira ticket | MERGE/upsert, clustered by `issue_key` |
| `issue_history` | `jira_curated` | Status change timeline | Append-only, partitioned by `changed_at` |

---

## Software Fingerprint & Duplicate Detection

Each unique combination of enabled software generates a **SHA256 fingerprint** (first 16 chars). When a new request arrives:

1. Fingerprint computed from sorted list of enabled software keys
2. Existing GCP images checked for matching `software-fingerprint` label
3. If match found: request marked as DUPLICATE, user notified, build skipped
4. If no match: build proceeds normally

This prevents building identical images multiple times — whether the request comes from Jira or direct GCS upload.

---

## Supported Software (22 Packages)

| Software | Key in JSON | Install Method | Binary Required |
|----------|-------------|---------------|-----------------|
| Google Chrome | `chrome` | Chocolatey | No |
| Git + GitHub Desktop | `git` | Chocolatey | No |
| Python (standalone) | `python` | Chocolatey | No |
| JupyterLab | `jupyterlab` | pip (requires Python) | No |
| Miniconda | `conda` | Chocolatey | No |
| Anaconda (full) | `anaconda` | Chocolatey | No |
| RStudio Desktop (OSS) | `rstudio` | Chocolatey | No |
| RStudio Pro / Posit Workbench | `rstudio_pro` | GCS binary | Yes |
| PyCharm Community | `pycharm_community` | Chocolatey | No |
| Visual Studio 2022 Community | `visual_studio_community` | Chocolatey | No |
| PowerShell 7+ | `powershell_core` | Chocolatey | No |
| Positron IDE | `positron` | GCS binary | Yes |
| ParaView | `paraview` | Chocolatey | No |
| Echoview v16+ | `echoview` | GCS binary | Yes |
| EchoSMs | `echosms` | GCS binary | Yes |
| EchoStack | `echostack` | GCS binary | Yes |
| MATLAB | `matlab` | GCS binary + license | Yes |
| NVIDIA GPU/GRID Drivers | `gpu_drivers` | GCS binary | Yes |
| Oracle Instant Client | `oracle_client` | GCS binary | Yes |
| AA-SI aalibrary | `aalibrary` | GCS binary | Yes |
| GCP Cloud SDK | `gcp_utilities` | Installer | No |
| Microsoft Excel | `excel` | Office Deployment Tool from GCS | Yes |

---

## Binary Software Bucket (GCS)

For software that cannot be installed via Chocolatey (licensed/proprietary), installers must be uploaded to a GCS bucket.

### Default Bucket: `org-sec-agents-bucket`

> **Where to change the bucket name:** Each Ansible playbook in `win2022-oracle-client-dev/packer/ansible-playbook/` references `gs://org-sec-agents-bucket/`:

```bash
grep -rl "org-sec-agents-bucket" win2022-oracle-client-dev/packer/ansible-playbook/
find win2022-oracle-client-dev/packer/ansible-playbook/ -name "*.yml" \
  -exec sed -i 's/org-sec-agents-bucket/YOUR-BUCKET-NAME/g' {} \;
```

<!-- CHANGE: Replace org-sec-agents-bucket with your actual software bucket name -->

### Required Folder Structure

```
gs://YOUR-BUCKET-NAME/
  |-- oracle/           # instantclient-basic + sqlplus ZIPs
  |-- echoview/         # EchoviewSetup.exe
  |-- matlab/           # matlab_installer.exe + installer_input.txt
  |-- posit/            # PositWorkbenchSetup.exe (RStudio Pro)
  |-- gpu/              # nvidia-grid-driver.exe
  |-- aalibrary/        # aalibrary-setup.exe
  |-- echosms/          # EchoSMsSetup.exe
  |-- echostack/        # EchoStackSetup.exe
  |-- office/           # officedeploymenttool.exe + configuration.xml
  +-- positron/         # PositronSetup.exe
```

---

## Networking & Firewall Requirements

| Rule | Source | Destination | Port | Purpose |
|------|--------|------------|------|---------|
| WinRM | Cloud Run subnet | Build VM | 5986 (TCP) | Ansible over WinRM |
| HTTPS egress | Cloud Run / Build VM | Internet/GCP APIs | 443 (TCP) | GCS, APIs, Chocolatey |
| IAP tunnel | Cloud Run subnet | Build VM | 22, 5986 | IAP-based private access |
| HTTPS ingress | Jira Cloud (internet) | Cloud Run (jira-ingest-api) | 443 (TCP) | **NEW** — Jira webhook |

> Cloud Run job uses `egress = ALL_TRAFFIC` through the VPC. No public IPs assigned to build VMs (`omit_external_ip = true`).
>
> The `jira-ingest-api` Cloud Run service is publicly accessible (Jira needs to reach it from the internet). Authentication is handled at the application level via the `X-Jira-Secret` header, not at the network level.

---

## Terraform Outputs

After `terraform apply`:

| Output | Description |
|--------|-------------|
| `request_bucket` | Bucket name for uploading request JSON (existing) |
| `audit_path` | GCS path for audit trail (existing) |
| `status_path` | GCS path for build status files (existing) |
| `pubsub_topic` | Pub/Sub topic for notifications (existing) |
| `jira_ingest_api_url` | **NEW** — Cloud Run URL for Jira webhook (use in Jira Automation) |
| `jira_raw_bucket` | **NEW** — GCS bucket for raw Jira payloads |
| `jira_bq_raw_dataset` | **NEW** — BigQuery dataset for raw Jira events |
| `jira_bq_curated_dataset` | **NEW** — BigQuery dataset for curated Jira data |

---

## Troubleshooting

### Jira webhook returns 401 Unauthorized
The `X-Jira-Secret` header value doesn't match the value in Secret Manager. Verify:
```bash
gcloud secrets versions access latest --secret=jira-webhook-secret --project=<PROJECT_ID>
```
Compare with the value in Jira Automation rule.

### Jira webhook returns 400 "No software selections found"
The Jira payload doesn't include a `software` dict with at least one item set to `true`. Check:
- Jira form checkboxes are mapped to the `software` object in the Automation body template
- Custom field IDs in the template match your Jira instance

<!-- CHANGE: Update custom field IDs in the Jira Automation body template to match
     your actual Jira field IDs. -->

### Jira webhook returns 400 "Missing required fields"
The payload is missing `ticket_id`/`issueKey` or `event`/`eventType`. Check Jira Automation body template.

### BigQuery tables empty after webhook
Check jira-processor Cloud Function logs:
```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="jira-processor"' \
  --project=<PROJECT_ID> --limit=10 --freshness=15m
```
Common issue: jira-processor-sa missing `roles/bigquery.dataEditor` or `roles/bigquery.jobUser`.

### "Insufficient free IP addresses in subnetwork"
The subnet is out of IPs. Either delete unused VMs or change to a larger subnet in `terraform/cloud_run_job.tf` (lines 28-29).

### "No URLs matched: gs://org-sec-agents-bucket/..."
Binary installer not uploaded. Upload the required installer to your software bucket or set that software to `false`.

### "Permission denied for all log views" (uploader auto-detection)
Add `roles/logging.viewer` to the `cf-process-request` service account:
```bash
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member="serviceAccount:cf-process-request@<PROJECT_ID>.iam.gserviceaccount.com" \
  --role="roles/logging.viewer"
```
> **Note:** This only affects direct GCS uploads. Jira requests include requester info in the payload, so auto-detection is skipped.

### "jq: invalid JSON text passed to --argjson"
The `SOFTWARE_JSON` variable has a quoting issue. Ensure `docker-entrypoint.sh` uses `--argjson software "${SOFTWARE_JSON:-"{}"}"`. Rebuild the Docker image after fixing.

### Recursive Eventarc trigger (429 rate limit errors)
The process-request function writes enriched JSON back to GCS. A `_processed` flag prevents re-processing. If you see loops, verify the function checks for `_processed` before processing.

### Build takes too long / times out
Default Cloud Run timeout is 7200s (2 hours). If more software is selected, increase timeout in `terraform/cloud_run_job.tf` line 24.

---

## Quick Reference: Key File Locations

| File | Purpose | Status |
|------|---------|--------|
| `terraform/variables.tf` | All configurable Terraform variables | Updated |
| `terraform/cloud_run_job.tf` | Cloud Run job + Cloud Scheduler | Existing |
| `terraform/eventarc.tf` | GCS bucket, Eventarc, Cloud Functions, Pub/Sub | Existing |
| `terraform/jira.tf` | **Jira integration: Cloud Run Service, BQ, GCS, IAM** | **NEW** |
| `cloudbuild-win2022-customizer.yaml` | CI/CD for Packer Docker image | Existing |
| `cloudbuild-jira-ingest.yaml` | **CI/CD for Jira ingest API Docker image** | **NEW** |
| `jira-ingest-api/main.py` | **FastAPI webhook receiver** | **NEW** |
| `jira-ingest-api/transform.py` | **Jira → image_config transform** | **NEW** |
| `jira-ingest-api/Dockerfile` | **Docker image for jira-ingest-api** | **NEW** |
| `terraform/functions/jira-processor/main.py` | **BigQuery loader Cloud Function** | **NEW** |
| `win2022-oracle-client-dev/docker-entrypoint.sh` | Main build orchestration script | Existing |
| `win2022-oracle-client-dev/packer/customize.pkr.hcl` | Packer template for Windows image | Existing |
| `win2022-oracle-client-dev/packer/ansible-playbook/main.yml` | Ansible main playbook | Existing |
| `win2022-oracle-client-dev/packer/scripts/Dockerfile` | Docker image for the Packer builder | Existing |
| `terraform/functions/process-request/main.py` | Pre-processor Cloud Function | Existing |
| `terraform/functions/notify-email/main.py` | Email notification Cloud Function | Existing |
| `sample-request.json` | Example JSON request (direct GCS upload) | Existing |

---

## Future Enhancements

<!-- These are NOT implemented yet. Add when needed. -->

- **Jira Ticket Callback:** After build completes, call Jira REST API to transition ticket to "Done" and add a comment with image/VM details. Requires storing a Jira API token in Secret Manager.
- **Approval Workflow:** Only trigger builds when Jira ticket reaches "Approved" status (add a second Automation rule on status transition).
- **Looker Dashboard:** Connect to `jira_curated` BigQuery dataset for team usage reports, build frequency, most-requested software.
- **Cost Tracking:** Tag images/VMs with Jira ticket ID for cost attribution in billing reports.
