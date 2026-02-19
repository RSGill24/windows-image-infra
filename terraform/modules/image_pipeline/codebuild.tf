data "google_project" "project" {
  project_id = var.project_id
}

resource "google_service_account" "packer_builder_sa" {
  account_id   = "packer-builder-sa"
  display_name = "Service Account for building packer images"
  project      = var.project_id
}

resource "google_pubsub_topic" "monthly_build_trigger_topic" {
  name    = "run-monthly-rebuilds"
  project = var.project_id
}

resource "google_cloud_scheduler_job" "monthly_rebuild" {
  name        = "golden-image-monthly-rebuild"
  description = "Triggers the monthly pam-wv latest image rebuild"
  schedule    = var.rebuild_schedule_cron
  time_zone   = "Etc/UTC"
  region      = var.region
  project     = var.project_id

  pubsub_target {
    topic_name = google_pubsub_topic.monthly_build_trigger_topic.id
    data       = base64encode(var.config.scheduler_data)
  }
}

resource "google_cloudbuild_trigger" "scheduled_trigger" {
  name            = "golden-image-build-scheduled"
  description     = "Builds the pam-wv latest image on a schedule via cloud scheduler/pubsub"
  disabled        = false
  project         = var.project_id
  service_account = google_service_account.packer_builder_sa.id

  source_to_build {
    uri       = "https://source.developers.google.com/p/${var.project_id}/r/${var.source_repo_name}"
    repo_type = "CLOUD_SOURCE_REPOSITORIES"
    ref       = "refs/heads/master"
  }

  pubsub_config {
    topic = google_pubsub_topic.monthly_build_trigger_topic.id
  }

  filename = var.cloudbuild_config_file
}

resource "google_project_iam_member" "scheduler_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "build_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.packer_builder_sa.email}"
}

resource "google_service_account_iam_member" "cb_service_account_users_packer_sa" {
  service_account_id = google_service_account.packer_builder_sa.id
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

resource "google_project_iam_member" "cb_source_repo_puller" {
  project = var.project_id
  role    = "roles/source.reader"
  member  = "serviceAccount:${google_service_account.packer_builder_sa.email}"
}

resource "google_service_account_iam_member" "packer_builder_members" {
  service_account_id = google_service_account.packer_builder_sa.id
  role               = "roles/iam.serviceAccountUser"
  for_each           = toset(concat(var.pamdata_admin, ["serviceAccount:${google_service_account.packer_builder_sa.email}"]))
  member             = each.key
}

resource "google_project_iam_member" "packer_image_builders" {
  project = var.project_id
  role    = google_project_iam_custom_role.image_builder_role.id
  member  = "serviceAccount:${google_service_account.packer_builder_sa.email}"
}

# NOTE: Reference the role from the iam module via variable if needed,
# or declare a local data source. Here we re-declare for module isolation.
resource "google_project_iam_custom_role" "image_builder_role" {
  role_id     = "image.builder.role"
  project     = var.project_id
  title       = "image.builder.role"
  description = "Custom role for packer image builders"
  permissions = var.config.image_builder_permissions
}

resource "google_project_iam_member" "iap_tunnel_users" {
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:${google_service_account.packer_builder_sa.email}"
}

resource "google_project_iam_member" "packer_sa_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.packer_builder_sa.email}"
}

resource "google_project_iam_member" "packer_sa_metrics" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.packer_builder_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "packer_build_secret_accessor" {
  project   = var.project_id
  secret_id = var.packer_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.packer_builder_sa.email}"
}
