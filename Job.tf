
# ADD THIS BLOCK TO YOUR EXISTING runjobs.tf


resource "google_cloud_run_v2_job" "windows" {
  name     = "windows-image-build"
  location = var.region
  project  = var.project_id

  labels = {
    env     = "dev"
    os      = "windows"
    managed = "terraform"
  }

  template {
    template {
      # ── Service Account ───────────────────────────────────
      service_account = "packer-win-sa@${var.project_id}.iam.gserviceaccount.com"

      # ── Timeout & Retries ─────────────────────────────────
      max_retries = 1
      timeout     = "3600s"

      # ── VPC Network (required for IAP tunnel to Windows VM)
      vpc_access {
        network_interfaces {
          network    = "app-network"
          subnetwork = "app-subnet1"
        }
        egress = "ALL_TRAFFIC"
      }

      # ── Container ─────────────────────────────────────────
      containers {
        name  = "windows-packer-builder"
        image = "${var.region}-docker.pkg.dev/${var.project_id}/packer-images/windows-packer-builder:latest"

        resources {
          limits = {
            cpu    = "2"
            memory = "2Gi"
          }
        }

        # ── Environment Variables ──────────────────────────
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "SOURCE_IMAGE_PROJECT_ID"
          value = "windows-cloud"
        }
        env {
          name  = "SOURCE_IMAGE_FAMILY"
          value = "windows-2022"
        }
        env {
          name  = "IMAGE_FAMILY"
          value = "pww-windows-2022-hardened"
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
          name  = "HARDENING_TARGET_DIR"
          value = "C:/Users/packer_user/hardening/"
        }
        env {
          name  = "PACKER_TEMPLATE"
          value = "harden_ww.pkr.hcl"
        }

        # ── WinRM Secret from Secret Manager ──────────────
        env {
          name = "WINRM_SECRET"
          value_source {
            secret_key_ref {
              secret  = "packer-winrm-password"
              version = "latest"
            }
          }
        }
      }
    }
  }
}
 