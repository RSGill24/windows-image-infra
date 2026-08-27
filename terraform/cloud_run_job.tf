################################################################################
# cloud_run_job.tf
#
# Cloud Run Job for the parameterized Windows image builder.
# Supports both ENV mode (backward-compatible) and JSON mode (Eventarc).
################################################################################

resource "google_cloud_run_v2_job" "windows_image_builder" {
  name                = "windows-image-builder"
  location            = var.region
  project             = var.project_id
  deletion_protection = false

  labels = {
    env     = "dev"
    os      = "windows"
    managed = "terraform"
  }

  template {
    template {
      service_account = "packer-win-sa@${var.project_id}.iam.gserviceaccount.com"

      max_retries = 1
      timeout     = "7200s" # 2 hours — more software = longer builds

      vpc_access {
        network_interfaces {
          network    = var.vm_network
          subnetwork = var.vm_subnet
        }
        egress = "ALL_TRAFFIC"
      }

      containers {
        name  = "windows-packer-builder"
        image = "${var.region}-docker.pkg.dev/${var.project_id}/packer-images/windows-packer-builder:latest"

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
          value = var.source_image_project_id != "" ? var.source_image_project_id : var.project_id
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
          value = "${var.region}-c"
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

        # ── Secret name (NOT the password itself) ───────────────────────────
        env {
          name  = "WINRM_SECRET"
          value = "packer-winrm-password"
        }

        # ── JSON mode / metadata config ─────────────────────────────────────
        # REQUEST_JSON_GCS is set at runtime by Eventarc trigger override
        env {
          name  = "REQUEST_JSON_GCS"
          value = ""
        }
        env {
          name  = "GCS_STATUS_BUCKET"
          value = local.request_bucket_name
        }
        # ── Email notification config (Gmail SMTP) ─────────────────────────
        env {
          name  = "GMAIL_SENDER_EMAIL"
          value = var.gmail_sender_email
        }
        env {
          name  = "GMAIL_APP_PASSWORD_SECRET"
          value = "gmail-app-password"
        }

        # ── VM Network / Shared VPC config ────────────────────────────────
        env {
          name  = "VM_NETWORK"
          value = var.vm_network
        }
        env {
          name  = "VM_SUBNET"
          value = var.vm_subnet
        }
        env {
          name  = "SHARED_VPC_HOST_PROJECT"
          value = var.shared_vpc_host_project
        }

        # ── Component-selection flags (ENV mode / defaults) ─────────────────
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
        env {
          name  = "INSTALL_CHROME"
          value = tostring(var.install_chrome)
        }
        env {
          name  = "INSTALL_GIT"
          value = tostring(var.install_git)
        }
        env {
          name  = "INSTALL_PYTHON"
          value = tostring(var.install_python)
        }
        env {
          name  = "INSTALL_JUPYTERLAB"
          value = tostring(var.install_jupyterlab)
        }
        env {
          name  = "INSTALL_POWERSHELL_CORE"
          value = tostring(var.install_powershell_core)
        }
        env {
          name  = "INSTALL_PYCHARM"
          value = tostring(var.install_pycharm)
        }
        env {
          name  = "INSTALL_VISUAL_STUDIO"
          value = tostring(var.install_visual_studio)
        }
        env {
          name  = "INSTALL_PARAVIEW"
          value = tostring(var.install_paraview)
        }
        env {
          name  = "INSTALL_ECHOVIEW"
          value = tostring(var.install_echoview)
        }
        env {
          name  = "INSTALL_MATLAB"
          value = tostring(var.install_matlab)
        }
        env {
          name  = "INSTALL_RSTUDIO_PRO"
          value = tostring(var.install_rstudio_pro)
        }
        env {
          name  = "INSTALL_POSITRON"
          value = tostring(var.install_positron)
        }
        env {
          name  = "INSTALL_ANACONDA"
          value = tostring(var.install_anaconda)
        }
        env {
          name  = "INSTALL_GPU_DRIVERS"
          value = tostring(var.install_gpu_drivers)
        }
        env {
          name  = "INSTALL_AALIBRARY"
          value = tostring(var.install_aalibrary)
        }
        env {
          name  = "INSTALL_ECHOSMS"
          value = tostring(var.install_echosms)
        }
        env {
          name  = "INSTALL_ECHOSTACK"
          value = tostring(var.install_echostack)
        }
        env {
          name  = "INSTALL_GCP_UTILITIES"
          value = tostring(var.install_gcp_utilities)
        }
        env {
          name  = "INSTALL_EXCEL"
          value = tostring(var.install_excel)
        }
      }
    }
  }
}

################################################################################
# Cloud Scheduler – triggers the Cloud Run job on a schedule (ENV mode)
################################################################################

resource "google_cloud_scheduler_job" "windows_image_builder_schedule" {
  name             = "windows-image-builder-schedule"
  description      = "Scheduled build of the parameterized Windows image"
  schedule         = "0 2 * * 1" # every Monday at 02:00 UTC
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
            { name = "INSTALL_ORACLE", value = tostring(var.install_oracle) },
            { name = "INSTALL_RSTUDIO", value = tostring(var.install_rstudio) },
            { name = "INSTALL_CONDA", value = tostring(var.install_conda) },
            { name = "INSTALL_CHROME", value = tostring(var.install_chrome) },
            { name = "INSTALL_GIT", value = tostring(var.install_git) },
            { name = "INSTALL_PYTHON", value = tostring(var.install_python) },
            { name = "INSTALL_JUPYTERLAB", value = tostring(var.install_jupyterlab) },
            { name = "INSTALL_POWERSHELL_CORE", value = tostring(var.install_powershell_core) },
            { name = "INSTALL_PYCHARM", value = tostring(var.install_pycharm) },
            { name = "INSTALL_VISUAL_STUDIO", value = tostring(var.install_visual_studio) },
            { name = "INSTALL_PARAVIEW", value = tostring(var.install_paraview) },
            { name = "INSTALL_ECHOVIEW", value = tostring(var.install_echoview) },
            { name = "INSTALL_MATLAB", value = tostring(var.install_matlab) },
            { name = "INSTALL_RSTUDIO_PRO", value = tostring(var.install_rstudio_pro) },
            { name = "INSTALL_POSITRON", value = tostring(var.install_positron) },
            { name = "INSTALL_ANACONDA", value = tostring(var.install_anaconda) },
            { name = "INSTALL_GPU_DRIVERS", value = tostring(var.install_gpu_drivers) },
            { name = "INSTALL_AALIBRARY", value = tostring(var.install_aalibrary) },
            { name = "INSTALL_ECHOSMS", value = tostring(var.install_echosms) },
            { name = "INSTALL_ECHOSTACK", value = tostring(var.install_echostack) },
            { name = "INSTALL_GCP_UTILITIES", value = tostring(var.install_gcp_utilities) },
            { name = "INSTALL_EXCEL", value = tostring(var.install_excel) }
          ]
        }]
      }
    }))

    headers = {
      "Content-Type" = "application/json"
    }
  }
}
