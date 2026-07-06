################################################################################
# eventarc.tf
#
# GCS request bucket + Eventarc trigger + pre-processor Cloud Function +
# Pub/Sub notification topic + email notification Cloud Function
#
# Flow:
#   GCS upload → Eventarc → process-request (CF)
#     ├── Logs audit metadata to /audit/
#     ├── Checks duplicate (software fingerprint)
#     ├── DUPLICATE? → Notify user, skip build
#     └── NEW? → Trigger Cloud Run job → build image → notify user
################################################################################

# ══════════════════════════════════════════════════════════════════════════════
# GCS Bucket: requests + audit + status metadata
# ══════════════════════════════════════════════════════════════════════════════

resource "google_storage_bucket" "image_builder_requests" {
  name                        = "${var.project_id}-image-builder-requests"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = false

  labels = {
    env     = "dev"
    managed = "terraform"
    purpose = "image-builder"
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
# Cloud Function 1: process-request (pre-processor)
#
# Triggered by Eventarc on GCS object.finalize in /requests/
# - Logs audit metadata
# - Checks for duplicate images (software fingerprint)
# - If duplicate → notify user, skip build
# - If new → trigger Cloud Run job
# ══════════════════════════════════════════════════════════════════════════════

# All components use the shared packer-win-sa service account.
# IAM roles are assigned manually (see README.md).

# Source code bucket for Cloud Functions
resource "google_storage_bucket" "function_source" {
  name                        = "${var.project_id}-cf-image-builder-src"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = true
}

# Package process-request function
data "archive_file" "process_request_zip" {
  type        = "zip"
  source_dir  = "${path.module}/functions/process-request"
  output_path = "${path.module}/functions/process-request.zip"
}

resource "google_storage_bucket_object" "process_request_source" {
  name   = "process-request-${data.archive_file.process_request_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.process_request_zip.output_path
}

resource "google_cloudfunctions2_function" "process_request" {
  name     = "image-builder-process-request"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "python312"
    entry_point = "process_request"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.process_request_source.name
      }
    }
  }

  service_config {
    max_instance_count = 3
    available_memory   = "512Mi"
    timeout_seconds    = 120

    service_account_email = "packer-win-sa@${var.project_id}.iam.gserviceaccount.com"

    environment_variables = {
      PROJECT_ID       = var.project_id
      REGION           = var.region
      BUCKET_NAME      = google_storage_bucket.image_builder_requests.name
      BUILDER_JOB_NAME = google_cloud_run_v2_job.windows_image_builder.name
    }
  }

  labels = {
    env     = "dev"
    managed = "terraform"
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# Eventarc trigger: GCS upload → process-request Cloud Function
# ══════════════════════════════════════════════════════════════════════════════

resource "google_eventarc_trigger" "image_builder_trigger" {
  name     = "image-builder-gcs-trigger"
  location = var.region
  project  = var.project_id

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }

  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.image_builder_requests.name
  }

  destination {
    cloud_run_service {
      service = "image-builder-process-request"
      region  = var.region
    }
  }

  service_account = "packer-win-sa@${var.project_id}.iam.gserviceaccount.com"

  labels = {
    env     = "dev"
    managed = "terraform"
  }
}

################################################################################
# Outputs
################################################################################

output "request_bucket" {
  value       = google_storage_bucket.image_builder_requests.name
  description = "Upload request JSON files to gs://<this-bucket>/requests/"
}

output "audit_path" {
  value       = "gs://${google_storage_bucket.image_builder_requests.name}/audit/"
  description = "Audit trail of all requests (who, what, when, action taken)"
}

output "status_path" {
  value       = "gs://${google_storage_bucket.image_builder_requests.name}/status/"
  description = "Build status metadata per request ID"
}

