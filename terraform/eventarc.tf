################################################################################
# eventarc.tf
#
# GCS request bucket + Eventarc trigger + Pub/Sub notification topic +
# Cloud Function for email alerts
################################################################################

# ── GCS Bucket for image build requests + status metadata ─────────────────────
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
      age = 90 # Clean up old status files after 90 days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
}

# ── Pub/Sub topic for build completion notifications ──────────────────────────
resource "google_pubsub_topic" "image_builder_notifications" {
  name    = "image-builder-notifications"
  project = var.project_id

  labels = {
    env     = "dev"
    managed = "terraform"
  }
}

# ── Pub/Sub subscription (for the Cloud Function) ────────────────────────────
resource "google_pubsub_subscription" "image_builder_email_sub" {
  name    = "image-builder-email-subscription"
  project = var.project_id
  topic   = google_pubsub_topic.image_builder_notifications.id

  ack_deadline_seconds = 60

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  labels = {
    env     = "dev"
    managed = "terraform"
  }
}

# ── Service Account for Eventarc trigger ─────────────────────────────────────
resource "google_service_account" "eventarc_trigger_sa" {
  account_id   = "eventarc-image-builder"
  display_name = "Eventarc Image Builder Trigger"
  project      = var.project_id
}

# Grant the Eventarc SA permission to invoke Cloud Run jobs
resource "google_project_iam_member" "eventarc_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.eventarc_trigger_sa.email}"
}

resource "google_project_iam_member" "eventarc_eventreceiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.eventarc_trigger_sa.email}"
}

# ── Eventarc trigger: fires when a JSON lands in /requests/ ──────────────────
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

  # Only trigger on files in the requests/ prefix
  matching_criteria {
    attribute = "name"
    value     = "requests/"
    operator  = "match-path-pattern"
  }

  destination {
    cloud_run_job {
      job    = google_cloud_run_v2_job.windows_image_builder.name
      region = var.region
    }
  }

  service_account = google_service_account.eventarc_trigger_sa.email

  labels = {
    env     = "dev"
    managed = "terraform"
  }
}

# ── Cloud Function: sends email on Pub/Sub notification ──────────────────────

# Source code bucket for the Cloud Function
resource "google_storage_bucket" "function_source" {
  name                        = "${var.project_id}-cf-image-builder-src"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = true
}

# Package the function source
data "archive_file" "notification_function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/functions/notify-email"
  output_path = "${path.module}/functions/notify-email.zip"
}

resource "google_storage_bucket_object" "notification_function_source" {
  name   = "notify-email-${data.archive_file.notification_function_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.notification_function_zip.output_path
}

resource "google_service_account" "notification_function_sa" {
  account_id   = "cf-image-notify"
  display_name = "Cloud Function – Image Builder Email Notification"
  project      = var.project_id
}

resource "google_cloudfunctions2_function" "notify_email" {
  name     = "image-builder-notify-email"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "python312"
    entry_point = "handle_pubsub"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.notification_function_source.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "256Mi"
    timeout_seconds    = 60

    service_account_email = google_service_account.notification_function_sa.email

    environment_variables = {
      SENDGRID_API_KEY_SECRET = var.sendgrid_api_key_secret
      FROM_EMAIL              = var.notification_from_email
      PROJECT_ID              = var.project_id
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.image_builder_notifications.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

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

output "status_bucket" {
  value       = google_storage_bucket.image_builder_requests.name
  description = "Build status metadata written to gs://<this-bucket>/status/<request-id>.json"
}

output "pubsub_topic" {
  value       = google_pubsub_topic.image_builder_notifications.name
  description = "Pub/Sub topic for build completion notifications"
}
