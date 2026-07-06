################################################################################
# jira.tf
#
# Jira Integration: webhook ingestion + raw storage + BigQuery analytics.
#
# All resources use the shared packer-win-sa service account.
#
# Flow:
#   Jira Automation → jira-ingest-api (Cloud Run Service)
#     ├── Writes raw JSON to gs://nmfs-winde-jira-raw-dev/jira/raw/...
#     ├── Transforms to image_config format
#     └── Writes to existing request bucket → triggers existing pipeline
#
#   GCS raw bucket → Eventarc → jira-processor (Cloud Function)
#     └── Loads into BigQuery (jira_raw + jira_curated)
################################################################################

locals {
  packer_sa_email = "packer-win-sa@${var.project_id}.iam.gserviceaccount.com"
}

# ══════════════════════════════════════════════════════════════════════════════
# IAM: Additional roles for packer-win-sa (Jira integration)
#
# packer-win-sa already has: storage.admin, secretmanager.secretAccessor,
# pubsub.publisher, logging.logWriter, compute.*, artifactregistry.writer,
# iam.serviceAccountUser, iap.tunnelResourceAccessor, cloudbuild.builds.builder
#
# Additional roles needed for Jira:
# ══════════════════════════════════════════════════════════════════════════════

# BigQuery write access for jira-processor CF
resource "google_project_iam_member" "packer_sa_bq_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${local.packer_sa_email}"
}

resource "google_project_iam_member" "packer_sa_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${local.packer_sa_email}"
}

# Eventarc event receiver for the Jira raw bucket trigger
resource "google_project_iam_member" "packer_sa_eventarc_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${local.packer_sa_email}"
}

# ══════════════════════════════════════════════════════════════════════════════
# GCS Bucket: Jira raw payloads
# ══════════════════════════════════════════════════════════════════════════════

resource "google_storage_bucket" "jira_raw" {
  name                        = var.jira_raw_bucket_name
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = true

  labels = {
    env     = "dev"
    managed = "terraform"
    purpose = "jira-raw"
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# Secret Manager: Jira webhook secret
# ══════════════════════════════════════════════════════════════════════════════

resource "google_secret_manager_secret" "jira_webhook_secret" {
  secret_id = var.jira_webhook_secret_name
  project   = var.project_id

  replication {
    auto {}
  }

  labels = {
    env     = "dev"
    managed = "terraform"
    purpose = "jira-webhook"
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# BigQuery: Datasets + Tables
# ══════════════════════════════════════════════════════════════════════════════

resource "google_bigquery_dataset" "jira_raw" {
  dataset_id  = "jira_raw"
  project     = var.project_id
  location    = var.region
  description = "Raw Jira event data from webhook ingestion"

  labels = {
    env     = "dev"
    managed = "terraform"
  }
}

resource "google_bigquery_dataset" "jira_curated" {
  dataset_id  = "jira_curated"
  project     = var.project_id
  location    = var.region
  description = "Curated Jira data: current issue state + history"

  labels = {
    env     = "dev"
    managed = "terraform"
  }
}

# ── jira_raw.issue_events ────────────────────────────────────────────────────

resource "google_bigquery_table" "issue_events" {
  dataset_id          = google_bigquery_dataset.jira_raw.dataset_id
  table_id            = "issue_events"
  project             = var.project_id
  deletion_protection = false

  schema = jsonencode([
    { name = "event_id",              type = "STRING",    mode = "REQUIRED", description = "Unique event UUID" },
    { name = "issue_key",             type = "STRING",    mode = "REQUIRED", description = "Jira issue key (e.g. NOAA-4)" },
    { name = "project_key",           type = "STRING",    mode = "NULLABLE", description = "Jira project key (e.g. NOAA)" },
    { name = "event_type",            type = "STRING",    mode = "NULLABLE", description = "Event type (e.g. jira_workstation_request)" },
    { name = "status",                type = "STRING",    mode = "NULLABLE", description = "Ticket status" },
    { name = "summary",               type = "STRING",    mode = "NULLABLE", description = "Ticket summary/title" },
    { name = "reporter_email",        type = "STRING",    mode = "NULLABLE", description = "Reporter email" },
    { name = "reporter_display_name", type = "STRING",    mode = "NULLABLE", description = "Reporter display name" },
    { name = "first_name",            type = "STRING",    mode = "NULLABLE", description = "Reporter first name" },
    { name = "group_name",            type = "STRING",    mode = "NULLABLE", description = "Team/group name" },
    { name = "approvers",             type = "STRING",    mode = "NULLABLE", description = "Approver name(s)" },
    { name = "raw_payload",           type = "STRING",    mode = "NULLABLE", description = "Full raw JSON payload" },
    { name = "gcs_uri",               type = "STRING",    mode = "NULLABLE", description = "GCS path to raw file" },
    { name = "ingested_at",           type = "TIMESTAMP", mode = "REQUIRED", description = "Ingestion timestamp" },
    { name = "created",               type = "TIMESTAMP", mode = "NULLABLE", description = "Jira ticket created time" },
    { name = "updated",               type = "TIMESTAMP", mode = "NULLABLE", description = "Jira ticket updated time" },
  ])

  time_partitioning {
    type  = "DAY"
    field = "ingested_at"
  }

  labels = {
    env     = "dev"
    managed = "terraform"
  }
}

# ── jira_curated.issue_current ───────────────────────────────────────────────

resource "google_bigquery_table" "issue_current" {
  dataset_id          = google_bigquery_dataset.jira_curated.dataset_id
  table_id            = "issue_current"
  project             = var.project_id
  deletion_protection = false

  schema = jsonencode([
    { name = "issue_key",             type = "STRING",    mode = "REQUIRED", description = "Jira issue key" },
    { name = "project_key",           type = "STRING",    mode = "NULLABLE", description = "Jira project key" },
    { name = "status",                type = "STRING",    mode = "NULLABLE", description = "Current ticket status" },
    { name = "summary",               type = "STRING",    mode = "NULLABLE", description = "Ticket summary" },
    { name = "reporter_email",        type = "STRING",    mode = "NULLABLE", description = "Reporter email" },
    { name = "group_name",            type = "STRING",    mode = "NULLABLE", description = "Team/group name" },
    { name = "approvers",             type = "STRING",    mode = "NULLABLE", description = "Approver name(s)" },
    { name = "image_build_request_id", type = "STRING",   mode = "NULLABLE", description = "Linked image builder request ID" },
    { name = "image_build_status",    type = "STRING",    mode = "NULLABLE", description = "Image build status" },
    { name = "last_event_type",       type = "STRING",    mode = "NULLABLE", description = "Most recent event type" },
    { name = "created",               type = "TIMESTAMP", mode = "NULLABLE", description = "Ticket created time" },
    { name = "updated",               type = "TIMESTAMP", mode = "NULLABLE", description = "Ticket updated time" },
    { name = "last_synced_at",        type = "TIMESTAMP", mode = "NULLABLE", description = "Last BQ sync time" },
  ])

  clustering = ["issue_key"]

  labels = {
    env     = "dev"
    managed = "terraform"
  }
}

# ── jira_curated.issue_history ───────────────────────────────────────────────

resource "google_bigquery_table" "issue_history" {
  dataset_id          = google_bigquery_dataset.jira_curated.dataset_id
  table_id            = "issue_history"
  project             = var.project_id
  deletion_protection = false

  schema = jsonencode([
    { name = "history_id",    type = "STRING",    mode = "REQUIRED", description = "Unique history entry UUID" },
    { name = "issue_key",     type = "STRING",    mode = "REQUIRED", description = "Jira issue key" },
    { name = "event_type",    type = "STRING",    mode = "NULLABLE", description = "Event type" },
    { name = "new_status",    type = "STRING",    mode = "NULLABLE", description = "New status after change" },
    { name = "changed_at",    type = "TIMESTAMP", mode = "REQUIRED", description = "When the change occurred" },
    { name = "raw_event_id",  type = "STRING",    mode = "NULLABLE", description = "FK to issue_events.event_id" },
  ])

  time_partitioning {
    type  = "DAY"
    field = "changed_at"
  }

  labels = {
    env     = "dev"
    managed = "terraform"
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# Cloud Run Service: jira-ingest-api
# ══════════════════════════════════════════════════════════════════════════════

resource "google_cloud_run_v2_service" "jira_ingest_api" {
  name                = "jira-ingest-api"
  location            = var.region
  project             = var.project_id
  deletion_protection = false

  labels = {
    env     = "dev"
    managed = "terraform"
    purpose = "jira-webhook"
  }

  template {
    service_account = local.packer_sa_email

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      name  = "jira-ingest-api"
      image = "${var.region}-docker.pkg.dev/${var.project_id}/packer-images/jira-ingest-api:latest"

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "REGION"
        value = var.region
      }
      env {
        name  = "RAW_BUCKET"
        value = google_storage_bucket.jira_raw.name
      }
      env {
        name  = "REQUEST_BUCKET"
        value = google_storage_bucket.image_builder_requests.name
      }
      env {
        name  = "WEBHOOK_SECRET_NAME"
        value = var.jira_webhook_secret_name
      }
    }
  }
}

# Allow unauthenticated access (Jira cannot send Google OAuth tokens)
# Security is handled at the app level via X-Jira-Secret header
resource "google_cloud_run_v2_service_iam_member" "jira_ingest_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.jira_ingest_api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ══════════════════════════════════════════════════════════════════════════════
# Cloud Function: jira-processor (GCS → BigQuery)
# ══════════════════════════════════════════════════════════════════════════════

data "archive_file" "jira_processor_zip" {
  type        = "zip"
  source_dir  = "${path.module}/functions/jira-processor"
  output_path = "${path.module}/functions/jira-processor.zip"
}

resource "google_storage_bucket_object" "jira_processor_source" {
  name   = "jira-processor-${data.archive_file.jira_processor_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.jira_processor_zip.output_path
}

resource "google_cloudfunctions2_function" "jira_processor" {
  name     = "jira-processor"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "python312"
    entry_point = "process_jira_event"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.jira_processor_source.name
      }
    }
  }

  service_config {
    max_instance_count = 3
    available_memory   = "512Mi"
    timeout_seconds    = 120

    service_account_email = local.packer_sa_email

    environment_variables = {
      PROJECT_ID         = var.project_id
      BQ_RAW_DATASET     = google_bigquery_dataset.jira_raw.dataset_id
      BQ_CURATED_DATASET = google_bigquery_dataset.jira_curated.dataset_id
    }
  }

  labels = {
    env     = "dev"
    managed = "terraform"
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# Eventarc: Jira raw bucket → jira-processor Cloud Function
# ══════════════════════════════════════════════════════════════════════════════

resource "google_eventarc_trigger" "jira_raw_trigger" {
  name     = "jira-raw-gcs-trigger"
  location = var.region
  project  = var.project_id

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }

  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.jira_raw.name
  }

  destination {
    cloud_run_service {
      service = element(split("/", google_cloudfunctions2_function.jira_processor.service_config[0].service), length(split("/", google_cloudfunctions2_function.jira_processor.service_config[0].service)) - 1)
      region  = var.region
    }
  }

  service_account = local.packer_sa_email

  depends_on = [google_cloudfunctions2_function.jira_processor]

  labels = {
    env     = "dev"
    managed = "terraform"
  }
}

################################################################################
# Outputs
################################################################################

output "jira_ingest_api_url" {
  value       = google_cloud_run_v2_service.jira_ingest_api.uri
  description = "URL for the Jira webhook endpoint (POST /webhook/jira)"
}

output "jira_raw_bucket" {
  value       = google_storage_bucket.jira_raw.name
  description = "GCS bucket for raw Jira payloads"
}

output "jira_bq_raw_dataset" {
  value       = google_bigquery_dataset.jira_raw.dataset_id
  description = "BigQuery dataset for raw Jira events"
}

output "jira_bq_curated_dataset" {
  value       = google_bigquery_dataset.jira_curated.dataset_id
  description = "BigQuery dataset for curated Jira data"
}
