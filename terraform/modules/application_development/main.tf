data "google_compute_image" "latest_ds_gi_image" {
  family  = var.ds_image_family
  project = var.project_id
}

resource "google_compute_instance" "app_dev_server1" {
  name         = "app-dev-server1"
  machine_type = var.app_dev_machine_type
  project      = var.project_id
  zone         = var.zone

  resource_policies = [
    "https://www.googleapis.com/compute/v1/projects/${var.project_id}/regions/${var.region}/resourcePolicies/dormant-patch-boot"
  ]

  metadata = {
    block-project-ssh-keys = true
    enable-osconfig        = true
  }

  labels = merge(var.common_labels, {
    ubuntu_force_reboot_patch_weds_7utc = true
  })

  boot_disk {
    device_name = "app-dev-server1"
    initialize_params {
      image = data.google_compute_image.latest_ds_gi_image.self_link
      size  = var.app_dev_disk_size_gb
      type  = var.app_dev_disk_type
    }
  }

  network_interface {
    subnetwork = var.app_subnet1_self_link
  }

  service_account {
    email  = var.app_dev_sa_email
    scopes = var.app_dev_sa_scopes
  }

  lifecycle {
    ignore_changes = [boot_disk]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

resource "google_artifact_registry_repository" "pamdata_docker_repo" {
  location      = var.region
  project       = var.project_id
  repository_id = var.docker_repo_id
  description   = "Repository for container images to run on pamdata infrastructure"
  format        = "DOCKER"

  docker_config {
    immutable_tags = false
  }
}
