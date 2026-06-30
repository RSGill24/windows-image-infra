# Jira Integration — Step-by-Step Testing Guide

Project: `big-mender-473219-r2`
Region: `us-east4`
SA: `packer-win-sa@big-mender-473219-r2.iam.gserviceaccount.com`

---

## Pre-Test: Verify Prerequisites

```bash
# Set variables for the entire test session
export PROJECT_ID="big-mender-473219-r2"
export REGION="us-east4"
export SA="packer-win-sa@${PROJECT_ID}.iam.gserviceaccount.com"
```

### Step 1: Enable BigQuery API (if not already)

```bash
gcloud services enable bigquery.googleapis.com --project=$PROJECT_ID
```

Expected: `Operation finished successfully` or `already enabled`

### Step 2: Add new IAM roles to packer-win-sa

```bash
# BigQuery (for jira-processor CF)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA" --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA" --role="roles/bigquery.jobUser"

# Eventarc (for Jira raw bucket trigger)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA" --role="roles/eventarc.eventReceiver"

# Run invoker (if not already assigned)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA" --role="roles/run.invoker"
```

Expected: Each command prints the updated IAM policy.

### Step 3: Verify Artifact Registry repo exists

```bash
gcloud artifacts repositories describe packer-images \
  --location=$REGION --project=$PROJECT_ID
```

Expected: Shows repo details. If not found:
```bash
gcloud artifacts repositories create packer-images \
  --repository-format=docker --location=$REGION --project=$PROJECT_ID
```

---

## Phase 1: Build the jira-ingest-api Docker Image

### Step 4: Build and push Docker image

```bash
cd ~/new-setup/windows-image-infra

gcloud builds submit \
  --config=cloudbuild-jira-ingest.yaml \
  --region=$REGION \
  --project=$PROJECT_ID .
```

Expected: Build succeeds. Last lines show:
```
DONE
images:
  - us-east4-docker.pkg.dev/big-mender-473219-r2/packer-images/jira-ingest-api:latest
```

If you get substitution errors, the YAML only uses `_PROJECT_ID`, `_REGION`, `_AR_REPO`, `_IMAGE_NAME` — none of the Packer-specific keys.

### Step 5: Verify image exists in Artifact Registry

```bash
gcloud artifacts docker images list \
  ${REGION}-docker.pkg.dev/${PROJECT_ID}/packer-images \
  --filter="package=${REGION}-docker.pkg.dev/${PROJECT_ID}/packer-images/jira-ingest-api" \
  --project=$PROJECT_ID
```

Expected: Shows `jira-ingest-api` with `latest` tag.

---

## Phase 2: Create the Jira Webhook Secret

### Step 6: Create secret in Secret Manager

```bash
# Generate a random secret
JIRA_SECRET=$(openssl rand -base64 32)
echo ">>> SAVE THIS: $JIRA_SECRET"

# Create the secret
gcloud secrets create jira-webhook-secret --project=$PROJECT_ID 2>/dev/null || true

# Add a version
echo -n "$JIRA_SECRET" | gcloud secrets versions add jira-webhook-secret \
  --data-file=- --project=$PROJECT_ID
```

Expected: `Created version [1] of the secret [jira-webhook-secret]`

### Step 7: Verify secret is readable

```bash
gcloud secrets versions access latest \
  --secret=jira-webhook-secret --project=$PROJECT_ID
```

Expected: Prints the secret value. Save this — you need it for all curl tests below.

---

## Phase 3: Deploy Terraform

### Step 8: Initialize and plan

```bash
cd ~/new-setup/windows-image-infra/terraform

terraform init
terraform plan -var="project_id=$PROJECT_ID"
```

Expected: Plan shows new resources to create:
- `google_storage_bucket.jira_raw`
- `google_bigquery_dataset.jira_raw`
- `google_bigquery_dataset.jira_curated`
- `google_bigquery_table.issue_events`
- `google_bigquery_table.issue_current`
- `google_bigquery_table.issue_history`
- `google_cloud_run_v2_service.jira_ingest_api`
- `google_cloudfunctions2_function.jira_processor`
- `google_eventarc_trigger.jira_raw_trigger`
- `google_secret_manager_secret.jira_webhook_secret`
- IAM bindings

Check that NO existing resources are being destroyed.

### Step 9: Apply

```bash
terraform apply -var="project_id=$PROJECT_ID"
```

Expected: All resources created successfully. Note the outputs:
```
jira_ingest_api_url = "https://jira-ingest-api-XXXXX-ue.a.run.app"
jira_raw_bucket = "nmfs-winde-jira-raw-dev"
```

Save the `jira_ingest_api_url` — you need it for all tests below.

```bash
# Save it to a variable
export JIRA_URL=$(terraform output -raw jira_ingest_api_url)
echo "Jira API URL: $JIRA_URL"
```

---

## Phase 4: Verify Infrastructure Exists

### Step 10: Check Cloud Run service

```bash
gcloud run services describe jira-ingest-api \
  --region=$REGION --project=$PROJECT_ID \
  --format="table(status.url, spec.template.spec.serviceAccountName)"
```

Expected: Shows URL and `packer-win-sa@...` as service account.

### Step 11: Check GCS bucket

```bash
gsutil ls -b gs://nmfs-winde-jira-raw-dev
```

Expected: `gs://nmfs-winde-jira-raw-dev/`

### Step 12: Check BigQuery datasets and tables

```bash
bq ls --project_id=$PROJECT_ID

bq ls ${PROJECT_ID}:jira_raw
bq ls ${PROJECT_ID}:jira_curated
```

Expected:
```
   datasetId
 -----------
  jira_raw
  jira_curated

     tableId      Type
 -------------- -------
  issue_events   TABLE

     tableId        Type
 ---------------- -------
  issue_current    TABLE
  issue_history    TABLE
```

### Step 13: Check Cloud Function

```bash
gcloud functions describe jira-processor \
  --region=$REGION --project=$PROJECT_ID \
  --format="table(state, serviceConfig.serviceAccountEmail)"
```

Expected: `ACTIVE` state, `packer-win-sa@...` as SA.

### Step 14: Check Eventarc trigger

```bash
gcloud eventarc triggers describe jira-raw-gcs-trigger \
  --location=$REGION --project=$PROJECT_ID
```

Expected: Shows trigger with `google.cloud.storage.object.v1.finalized` on `nmfs-winde-jira-raw-dev` bucket.

---

## Phase 5: Test the API Endpoint

### Step 15: Health check

```bash
curl -s ${JIRA_URL}/health | jq .
```

Expected:
```json
{
  "status": "ok",
  "service": "jira-ingest-api"
}
```

If you get `403 Forbidden`: The `allUsers` invoker IAM hasn't propagated yet. Wait 1-2 minutes and retry.

### Step 16: Test without secret (should fail)

```bash
curl -s -w "\nHTTP_CODE: %{http_code}\n" \
  -X POST ${JIRA_URL}/webhook/jira \
  -H "Content-Type: application/json" \
  -d '{"event": "test"}'
```

Expected: `HTTP_CODE: 401` and `"Missing X-Jira-Secret header"`

### Step 17: Test with wrong secret (should fail)

```bash
curl -s -w "\nHTTP_CODE: %{http_code}\n" \
  -X POST ${JIRA_URL}/webhook/jira \
  -H "Content-Type: application/json" \
  -H "X-Jira-Secret: wrong-secret" \
  -d '{"event": "test"}'
```

Expected: `HTTP_CODE: 401` and `"Invalid webhook secret"`

### Step 18: Test with missing required fields (should fail)

```bash
JIRA_SECRET=$(gcloud secrets versions access latest --secret=jira-webhook-secret --project=$PROJECT_ID)

curl -s -w "\nHTTP_CODE: %{http_code}\n" \
  -X POST ${JIRA_URL}/webhook/jira \
  -H "Content-Type: application/json" \
  -H "X-Jira-Secret: $JIRA_SECRET" \
  -d '{"summary": "missing ticket_id and event"}'
```

Expected: `HTTP_CODE: 400` and `"Missing required fields: issue_key, event_type"`

### Step 19: Test with no software (should fail)

```bash
curl -s -w "\nHTTP_CODE: %{http_code}\n" \
  -X POST ${JIRA_URL}/webhook/jira \
  -H "Content-Type: application/json" \
  -H "X-Jira-Secret: $JIRA_SECRET" \
  -d '{
    "event": "jira_workstation_request",
    "ticket_id": "NOAA-TEST-0",
    "reporter_email": "test@example.com",
    "first_name": "Test",
    "group_name": "GARFO",
    "summary": "No software selected"
  }'
```

Expected: `HTTP_CODE: 400` and `"No software selections found"`

---

## Phase 6: Full End-to-End Test (Happy Path)

### Step 20: Send a valid Jira webhook

```bash
curl -s -w "\nHTTP_CODE: %{http_code}\n" \
  -X POST ${JIRA_URL}/webhook/jira \
  -H "Content-Type: application/json" \
  -H "X-Jira-Secret: $JIRA_SECRET" \
  -d '{
    "event": "jira_workstation_request",
    "eventType": "issue_created",
    "sourceSystem": "jira",
    "ticket_id": "NOAA-TEST-1",
    "issueKey": "NOAA-TEST-1",
    "projectKey": "NOAA",
    "status": "Submitted",
    "summary": "Test workstation - Chrome Git Python",
    "created": "2026-06-29T12:00:00Z",
    "updated": "2026-06-29T12:00:00Z",
    "reporter_email": "testuser@example.com",
    "reporter_display_name": "Test User",
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
```

Expected: `HTTP_CODE: 200` and response like:
```json
{
  "status": "accepted",
  "issue_key": "NOAA-TEST-1",
  "raw_path": "gs://nmfs-winde-jira-raw-dev/jira/raw/project_key=NOAA/date=2026-06-29/issue-NOAA-TEST-1.json",
  "request_path": "gs://big-mender-473219-r2-image-builder-requests/requests/jira-NOAA-TEST-1-XXXXXX.json",
  "message": "Jira ticket NOAA-TEST-1 accepted. Image build pipeline triggered."
}
```

### Step 21: Verify raw JSON in GCS

```bash
gsutil ls gs://nmfs-winde-jira-raw-dev/jira/raw/project_key=NOAA/

gsutil cat gs://nmfs-winde-jira-raw-dev/jira/raw/project_key=NOAA/date=*/issue-NOAA-TEST-1.json | jq .
```

Expected: The exact Jira payload you sent, pretty-printed.

### Step 22: Verify transformed JSON in request bucket

```bash
gsutil ls gs://${PROJECT_ID}-image-builder-requests/requests/ | grep jira-NOAA-TEST-1

# Read it
gsutil cat gs://${PROJECT_ID}-image-builder-requests/requests/jira-NOAA-TEST-1-*.json | jq .
```

Expected: Transformed `image_config` format:
```json
{
  "image_config": {
    "image_name": "nmfs-windows-software-2022-noaa-test-1-...",
    "create_vm": true,
    "keep_image": true,
    "software": {
      "chrome": true,
      "git": true,
      "python": true,
      "gcp_utilities": true,
      "conda": false,
      "rstudio": false,
      ...
    }
  },
  "requester": {
    "name": "Test",
    "email": "testuser@example.com",
    "team": "GARFO"
  },
  "jira_metadata": {
    "ticket_id": "NOAA-TEST-1",
    "project_key": "NOAA",
    ...
  }
}
```

### Step 23: Verify BigQuery (jira-processor CF)

Wait 30-60 seconds for the Eventarc → jira-processor pipeline to run, then:

```bash
# Raw events table
bq query --use_legacy_sql=false \
  "SELECT event_id, issue_key, event_type, reporter_email, ingested_at
   FROM \`${PROJECT_ID}.jira_raw.issue_events\`
   ORDER BY ingested_at DESC LIMIT 5"

# Current state table
bq query --use_legacy_sql=false \
  "SELECT issue_key, status, reporter_email, group_name, last_synced_at
   FROM \`${PROJECT_ID}.jira_curated.issue_current\`
   ORDER BY last_synced_at DESC LIMIT 5"

# History table
bq query --use_legacy_sql=false \
  "SELECT issue_key, event_type, new_status, changed_at
   FROM \`${PROJECT_ID}.jira_curated.issue_history\`
   ORDER BY changed_at DESC LIMIT 5"
```

Expected: All 3 tables have a row for `NOAA-TEST-1`.

If tables are empty, check jira-processor logs:
```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="jira-processor"' \
  --project=$PROJECT_ID --limit=10 --freshness=10m \
  --format="table(timestamp,textPayload)"
```

### Step 24: Verify existing pipeline triggered (process-request CF)

```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="image-builder-process-request"' \
  --project=$PROJECT_ID --limit=15 --freshness=10m \
  --format="table(timestamp,textPayload)"
```

Expected: Logs showing:
```
[START] Processing request: gs://big-mender-...-requests/requests/jira-NOAA-TEST-1-...
[JSON] Requester provided in JSON: {'name': 'Test', 'email': 'testuser@example.com', 'team': 'GARFO'}
[REQUEST] Software: chrome, gcp_utilities, git, python
[FINGERPRINT] abc123...
[NEW] No existing image with fingerprint ... — triggering build
[CLOUD RUN] Triggered job: windows-image-builder
```

### Step 25: Verify Cloud Run Job kicked off

```bash
gcloud run jobs executions list \
  --job=windows-image-builder \
  --region=$REGION --project=$PROJECT_ID \
  --limit=3
```

Expected: A new execution in `RUNNING` or `SUCCEEDED` state.

---

## Phase 7: Test Duplicate Detection

### Step 26: Send the same webhook again (same software)

```bash
curl -s -w "\nHTTP_CODE: %{http_code}\n" \
  -X POST ${JIRA_URL}/webhook/jira \
  -H "Content-Type: application/json" \
  -H "X-Jira-Secret: $JIRA_SECRET" \
  -d '{
    "event": "jira_workstation_request",
    "ticket_id": "NOAA-TEST-2",
    "reporter_email": "another@example.com",
    "first_name": "Another",
    "group_name": "SEFSC",
    "summary": "Same software as NOAA-TEST-1",
    "software": {
      "chrome": true,
      "git": true,
      "python": true,
      "gcp_utilities": true
    }
  }'
```

Expected: `HTTP_CODE: 200` (the ingest API accepts it).

Then check process-request logs:
```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="image-builder-process-request"' \
  --project=$PROJECT_ID --limit=10 --freshness=5m \
  --format="table(timestamp,textPayload)"
```

Expected (if NOAA-TEST-1 build already finished):
```
[DUPLICATE] Image already exists: nmfs-windows-software-2022-...
```

If NOAA-TEST-1 build is still running, it will trigger a second build (duplicates are only detected if a completed image with the same fingerprint exists).

---

## Phase 8: Test with Different Software

### Step 27: Send webhook with different software selection

```bash
curl -s -w "\nHTTP_CODE: %{http_code}\n" \
  -X POST ${JIRA_URL}/webhook/jira \
  -H "Content-Type: application/json" \
  -H "X-Jira-Secret: $JIRA_SECRET" \
  -d '{
    "event": "jira_workstation_request",
    "ticket_id": "NOAA-TEST-3",
    "reporter_email": "scientist@example.com",
    "first_name": "Scientist",
    "group_name": "NWFSC",
    "summary": "Data science workstation",
    "software": {
      "chrome": true,
      "git": true,
      "python": true,
      "conda": true,
      "jupyterlab": true,
      "rstudio": true,
      "positron": true,
      "gcp_utilities": true
    }
  }'
```

Expected: `HTTP_CODE: 200`. Different fingerprint → new build triggered.

Verify:
```bash
# Check BQ has 3 events now
bq query --use_legacy_sql=false \
  "SELECT issue_key, event_type, reporter_email
   FROM \`${PROJECT_ID}.jira_raw.issue_events\`
   ORDER BY ingested_at DESC LIMIT 5"
```

---

## Phase 9: Cleanup Test Data

After testing, clean up so test data doesn't trigger real builds or waste resources.

### Step 28: Delete test files from GCS

```bash
# Raw Jira payloads
gsutil -m rm -r gs://nmfs-winde-jira-raw-dev/jira/raw/project_key=NOAA/

# Transformed request files (to stop any pending builds)
gsutil ls gs://${PROJECT_ID}-image-builder-requests/requests/jira-NOAA-TEST-* 2>/dev/null && \
gsutil -m rm gs://${PROJECT_ID}-image-builder-requests/requests/jira-NOAA-TEST-*

# Audit and status files
gsutil ls gs://${PROJECT_ID}-image-builder-requests/audit/ 2>/dev/null && \
gsutil -m rm gs://${PROJECT_ID}-image-builder-requests/audit/*TEST*
gsutil ls gs://${PROJECT_ID}-image-builder-requests/status/ 2>/dev/null && \
gsutil -m rm gs://${PROJECT_ID}-image-builder-requests/status/*TEST*
```

### Step 29: Delete test rows from BigQuery

```bash
bq query --use_legacy_sql=false \
  "DELETE FROM \`${PROJECT_ID}.jira_raw.issue_events\` WHERE issue_key LIKE 'NOAA-TEST-%'"

bq query --use_legacy_sql=false \
  "DELETE FROM \`${PROJECT_ID}.jira_curated.issue_current\` WHERE issue_key LIKE 'NOAA-TEST-%'"

bq query --use_legacy_sql=false \
  "DELETE FROM \`${PROJECT_ID}.jira_curated.issue_history\` WHERE issue_key LIKE 'NOAA-TEST-%'"
```

### Step 30: (Optional) Delete test images

If any test builds completed and created GCP images:
```bash
gcloud compute images list --project=$PROJECT_ID \
  --filter="name~noaa-test" --format="table(name,family,creationTimestamp)"

# Delete each test image
# gcloud compute images delete IMAGE_NAME --project=$PROJECT_ID
```

---

## Quick Troubleshooting

| Problem | Check | Fix |
|---------|-------|-----|
| Health check returns 403 | `allUsers` IAM not propagated | Wait 2 mins, or check `gcloud run services get-iam-policy jira-ingest-api --region=$REGION` |
| 401 on webhook | Secret mismatch | `gcloud secrets versions access latest --secret=jira-webhook-secret` and compare |
| 200 from API but no file in raw bucket | Storage permission | Check `packer-win-sa` has `roles/storage.admin` |
| Raw file exists but BQ empty | jira-processor CF failed | Check CF logs: `gcloud logging read 'resource.labels.service_name="jira-processor"'` |
| Request file exists but no build triggered | process-request CF failed | Check CF logs: `gcloud logging read 'resource.labels.service_name="image-builder-process-request"'` |
| Cloud Run Job fails with jq error | Old Docker image | Rebuild: `gcloud builds submit --config=cloudbuild-win2022-customizer.yaml --region=$REGION .` |
| Terraform plan shows destroy | SA resource removed | Expected — we removed separate SAs. The `packer-win-sa` roles are assigned manually. |

---

## Test Summary Checklist

- [ ] Step 1-3: Prerequisites (API, IAM, Artifact Registry)
- [ ] Step 4-5: Docker image built and pushed
- [ ] Step 6-7: Webhook secret created and readable
- [ ] Step 8-9: Terraform plan clean, apply successful
- [ ] Step 10-14: All infra resources exist
- [ ] Step 15: Health check returns 200
- [ ] Step 16-17: Auth rejection works (401)
- [ ] Step 18-19: Validation rejection works (400)
- [ ] Step 20: Valid webhook returns 200
- [ ] Step 21: Raw JSON in GCS raw bucket
- [ ] Step 22: Transformed JSON in request bucket
- [ ] Step 23: BigQuery tables populated
- [ ] Step 24: process-request CF logs show processing
- [ ] Step 25: Cloud Run Job execution started
- [ ] Step 26: Duplicate detection works
- [ ] Step 27: Different software triggers new build
- [ ] Step 28-30: Test data cleaned up
