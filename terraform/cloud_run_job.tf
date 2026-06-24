################################################################################
# variables.tf  –  declare these in your root module
################################################################################
# variable "project_id"  { type = string }
# variable "region"      { type = string }
# variable "install_oracle"  { type = bool   default = false }
# variable "install_rstudio" { type = bool   default = false }
# variable "install_conda"   { type = bool   default = false }
################################################################################

resource "google_cloud_run_v2_job" "windows_image_builder" {
  name     = "windows-image-builder"
  location = var.region
  project  = var.project_id

  labels = {
    env     = "dev"
    os      = "windows"
    managed = "terraform"
  }

  template {
    template {
      service_account = "packer-win-sa@${var.project_id}.iam.gserviceaccount.com"

      max_retries = 1
      timeout     = "3600s"

      vpc_access {
        network_interfaces {
          network    = "app-network"
          subnetwork = "app-subnet1"
        }
        egress = "ALL_TRAFFIC"
      }

      containers {
        name  = "windows-packer-builder"
        image = "${var.region}-docker.pkg.dev/${var.project_id}/packer-images/windows-packer-customizer:latest"

        resources {
          limits = {
            cpu    = "2"
            memory = "4Gi"
          }
        }

        # ── Infra variables ─────────────────────────────────────────────────
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "SOURCE_IMAGE_PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "SOURCE_IMAGE_FAMILY"
          value = "nmfs-windows-2022"
        }
        env {
          name  = "IMAGE_FAMILY"
          value = "pww-windows-2022-customized-dev"
        }
        env {
          name  = "ZONE"
          value = "${var.region}-b"
        }
        env {
          name  = "MACHINE_TYPE"
          value = "e2-standard-8"
        }
        env {
          name  = "SERVICE_ACCOUNT_EMAIL"
          value = "packer-win-sa@${var.project_id}.iam.gserviceaccount.com"
        }
        env {
          name  = "INSTALLATION_TARGET_DIR"
          value = "C:/Users/packer_user/installation/"
        }
        env {
          name  = "INSTALLATION_SOURCE_DIR"
          value = "./ansible-playbook"
        }
        env {
          name  = "PACKER_TEMPLATE"
          value = "customize.pkr.hcl"
        }

        # ── Component-selection flags ───────────────────────────────────────
        env {
          name  = "INSTALL_ORACLE"
          value = tostring(var.install_oracle)
        }
        env {
          name  = "INSTALL_RSTUDIO"
          value = tostring(var.install_rstudio)
        }
        env {
          name  = "INSTALL_CONDA"
          value = tostring(var.install_conda)
        }

        # ── Secret name (NOT the password itself) ───────────────────────────
        # docker-entrypoint.sh calls:
        #   gcloud secrets versions access latest --secret $WINRM_SECRET
        # So this must be the Secret Manager secret ID, not the password value.
        env {
          name  = "WINRM_SECRET"
          value = "packer-winrm-password"
        }
      }
    }
  }
}

################################################################################
# Cloud Scheduler – triggers the Cloud Run job on a schedule
################################################################################

resource "google_cloud_scheduler_job" "windows_image_builder_schedule" {
  name             = "windows-image-builder-schedule"
  description      = "Scheduled build of the parameterized Windows image"
  schedule         = "0 2 * * 1"   # every Monday at 02:00 UTC
  time_zone        = "UTC"
  project          = var.project_id
  region           = var.region
  attempt_deadline = "1800s"

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.windows_image_builder.name}:run"

    oauth_token {
      service_account_email = "packer-win-sa@${var.project_id}.iam.gserviceaccount.com"
    }

    # ── Runtime overrides ───────────────────────────────────────────────────
    body = base64encode(jsonencode({
      overrides = {
        containerOverrides = [{
          name = "windows-packer-builder"
          env = [
            { name = "INSTALL_ORACLE",  value = tostring(var.install_oracle)  },
            { name = "INSTALL_RSTUDIO", value = tostring(var.install_rstudio) },
            { name = "INSTALL_CONDA",   value = tostring(var.install_conda)   }
          ]
        }]
      }
    }))

    headers = {
      "Content-Type" = "application/json"
    }
  }
}

