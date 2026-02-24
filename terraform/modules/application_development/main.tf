#infra for general application development use.
#
#docker server

#create instance
#
#post provision steps:
##to add users to docker group (done post provision / login, since OSlogin users will not exist until login.
##sudo usermod -aG docker $USER
##newgrp docker

resource "google_compute_instance" "app_dev_server1" {
  name         = var.app_dev_instance_name
  machine_type = var.app_dev_machine_type
  project      = var.project_id
  zone         = var.zone1

  resource_policies = [
    "https://www.googleapis.com/compute/v1/projects/${var.project_id}/regions/${var.region1}/resourcePolicies/dormant-patch-boot"
  ]

  metadata = {
    block-project-ssh-keys = true
    enable-osconfig        = true
  }

  labels = {
    environment                         = var.environment
    noaa_fismaid                        = var.system_id
    noaa_lineoffice                     = var.lineoffice
    noaa_taskorder                      = var.taskorder
    noaa_environment                    = var.environment
    noaa_applicationid                  = var.application_id
    noaa_project_id                     = var.project_id
    ubuntu_force_reboot_patch_weds_7utc = true
  }

  boot_disk {
    device_name = var.app_dev_instance_name

    initialize_params {
      image = "projects/${var.ds_image_project_id}/global/images/family/${var.ds_image_family}"
      size  = var.app_dev_boot_disk_size_gb
      type  = var.app_dev_boot_disk_type
    }
  }

  network_interface {
    subnetwork = var.app_subnet1_self_link
  }

  service_account {
    email  = var.app_dev_service_account_email
    scopes = ["cloud-platform"]
  }

  #allow for updates to the image family to happen without needing replacement on instance.
  lifecycle {
    ignore_changes = [boot_disk]
  }

  shielded_instance_config {
    enable_secure_boot          = "true"
    enable_vtpm                 = "true"
    enable_integrity_monitoring = "true"
  }
}

#docker registry

resource "google_artifact_registry_repository" "pamdata_docker_repo" {
  location      = var.region1
  repository_id = var.docker_repo_id
  description   = var.docker_repo_description
  format        = "DOCKER"

  docker_config {
    immutable_tags = false
  }
}

