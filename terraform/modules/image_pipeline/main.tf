#currently, reimage after every patch tuesday, so that newly provisioned instances don't come OOB with criticals.
#set up a time triggered build process with cloud scheduler, pubsub, and cloud build.

resource "google_cloud_scheduler_job" "monthly_rebuild" {
  name        = "golden-image-monthly-rebuild"
  description = "Triggers the monthly pam-wv latest image rebuild"
  # This cron schedule midnight on the 16th, right at the end of the batch window.
  schedule  = var.cloudbuild_schedule
  time_zone = var.cloudbuild_time_zone
  region    = var.region1

  pubsub_target {
    topic_name = google_pubsub_topic.monthly_build_trigger_topic.id
    data       = base64encode("Run monthly build")
  }
}

resource "google_pubsub_topic" "monthly_build_trigger_topic" {
  name = var.cloudbuild_pubsub_topic_name
}

resource "google_cloudbuild_trigger" "scheduled_trigger" {
  name            = var.cloudbuild_trigger_name
  description     = "Builds the pam-wv latest image on a schedule via cloud scheduler/pubsub"
  disabled        = false
  service_account = google_service_account.packer_builder_sa.id

  source_to_build {
    uri       = var.cloudbuild_repo_uri
    repo_type = "CLOUD_SOURCE_REPOSITORIES"
    ref       = var.cloudbuild_branch_ref
  }

  pubsub_config {
    topic = google_pubsub_topic.monthly_build_trigger_topic.id
  }

  filename = var.cloudbuild_filename
}

data "google_project" "project" {}

#roles:
#in addition to those here and in afsc standard-iac, also need secret accessor for secret packer_user_password, needs to stop a specific instance, needs to list images

#service account for packer builder sa.
resource "google_service_account" "packer_builder_sa" {
  account_id   = var.packer_builder_service_account_id
  display_name = var.packer_builder_service_account_display_name
  project      = var.project_id
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

#binding for packer builder sa, includes itself for proper function
resource "google_service_account_iam_member" "packer_builder_members" {
  service_account_id = google_service_account.packer_builder_sa.id
  role               = "roles/iam.serviceAccountUser"
  # NOTE: The screenshot truncates the variable name for the admin list. Using a safe guess here.
  for_each = toset(concat(var.pamdata_admin, ["serviceAccount:${google_service_account.packer_builder_sa.email}"]))
  member   = each.key
}

#custom role
resource "google_project_iam_member" "packer_image_builders" {
  project = var.project_id
  role    = var.image_builder_role_id
  member  = "serviceAccount:${google_service_account.packer_builder_sa.email}"
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

#allow to read secret:
# Grant the "Secret Accessor" role to a specific service account
resource "google_secret_manager_secret_iam_member" "packer_build_secret_accessor" {
  project   = var.project_id
  secret_id = var.packer_user_password_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.packer_builder_sa.email}"
}

