data "google_compute_image" "latest_pam_windows_workstation" {
  family  = var.windows_workstation_image_family
  project = var.windows_workstation_image_project_id
}

data "google_compute_image" "lastest_pam_ww_template" {
  family  = var.windows_template_image_family
  project = var.windows_template_image_project_id
}

##instance representing latest workstation template in family
resource "google_compute_instance" "lastest_pam_ww_template_instance" {
  name         = "lastest-pam-ww-template-instance"
  machine_type = var.windows_machine_type
  project      = var.project_id
  zone         = var.zone1

  resource_policies = ["https://www.googleapis.com/compute/v1/projects/${var.project_id}/regions/${var.region1}/resourcePolicies/patch-boot-shutdown"]

  metadata = {
    block-project-ssh-keys = true
    enable-osconfig        = true
  }

  labels = {
    environment                     = var.environment
    noaa_fismaid                    = var.system_id
    noaa_lineoffice                 = var.lineoffice
    noaa_taskorder                  = var.taskorder
    noaa_environment                = var.environment
    noaa_applicationid              = var.application_id
    noaa_project_id                 = var.project_id
    windows_force_reboot_patch_15th = true
    product_name                    = "pam-ww"
  }

  boot_disk {
    device_name = "lastest-pam-ww-template-instance"
    #if spawning multiple:
    initialize_params {
      #image = "projects/windows-cloud/global/images/family/windows-2022"
      image = data.google_compute_image.lastest_pam_ww_template.name
      size  = "250"
      type  = "pd-standard"
    }
  }

  #allow for updates to the image family to happen without needing replacement on instance.
  lifecycle {
    ignore_changes = [metadata["windows-keys"]]
  }

  network_interface {
    subnetwork = var.app_subnet2_self_link
  }

  service_account {
    email  = var.windows_workstation_sa_email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = "true"
    enable_vtpm                 = "true"
    enable_integrity_monitoring = "true"
  }
}

##user instances

##instance representing latest workstation in family
resource "google_compute_instance" "user_pam_windows_workstation_instance" {
  for_each = toset(var.pam_ww_users1)

  name         = "${lower(replace(replace(replace(each.value, "/[^a-z0-9]+/", "-"), "user-", ""), "noaa-gov-", ""))}-pam-ww"
  machine_type = var.windows_machine_type
  project      = var.project_id
  zone         = var.zone1

  resource_policies = ["https://www.googleapis.com/compute/v1/projects/${var.project_id}/regions/${var.region1}/resourcePolicies/patch-boot-shutdown"]

  metadata = {
    block-project-ssh-keys = true
    enable-osconfig        = true
  }

  labels = {
    environment                     = var.environment
    noaa_fismaid                    = var.system_id
    noaa_lineoffice                 = var.lineoffice
    noaa_taskorder                  = var.taskorder
    noaa_environment                = var.environment
    noaa_applicationid              = var.application_id
    noaa_project_id                 = var.project_id
    windows_force_reboot_patch_15th = true
    product_name                    = "pam-ww"
  }

  boot_disk {
    device_name = "${lower(replace(replace(replace(each.value, "/[^a-z0-9]+/", "-"), "user-", ""), "noaa-gov-", ""))}-pam-ww"
    initialize_params {
      image = data.google_compute_image.latest_pam_windows_workstation.name
      size  = "250"
      type  = "pd-standard"
    }
  }

  #allow for updates to the image family to happen without needing replacement on instance.
  #machine type added to ignore, so users can adjust this as needed
  lifecycle {
    ignore_changes = [metadata["windows-keys"], boot_disk, machine_type, network_interface, labels["product_name"]]
  }

  network_interface {
    subnetwork = var.app_subnet2_self_link
  }

  service_account {
    email  = var.windows_workstation_sa_email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = "true"
    enable_vtpm                 = "true"
    enable_integrity_monitoring = true
  }
}

data "google_compute_disk" "gpu_env_disk3" {
  count   = var.enable_gpu_workstation ? 1 : 0
  name    = var.gpu_boot_disk_name
  project = var.gpu_boot_disk_project_id
  zone    = var.zone1
}

##custom instance
resource "google_compute_instance" "dwoodrich_pam_ww_gpu2" {
  count        = var.enable_gpu_workstation ? 1 : 0
  name         = "dwoodrich-pam-ww-gpu2"
  machine_type = var.windows_gpu_machine_type
  project      = var.project_id
  zone         = var.zone1

  scheduling {
    on_host_maintenance = "TERMINATE"
  }

  resource_policies = ["https://www.googleapis.com/compute/v1/projects/${var.project_id}/regions/${var.region1}/resourcePolicies/patch-boot-shutdown"]

  metadata = {
    block-project-ssh-keys = true
    enable-osconfig        = true
  }

  labels = {
    environment                     = var.environment
    noaa_fismaid                    = var.system_id
    noaa_lineoffice                 = var.lineoffice
    noaa_taskorder                  = var.taskorder
    noaa_environment                = var.environment
    noaa_applicationid              = var.application_id
    noaa_project_id                 = var.project_id
    windows_force_reboot_patch_15th = true
    product_name                    = "pam-ww-gpu"
  }

  boot_disk {
    auto_delete = false
    source      = data.google_compute_disk.gpu_env_disk3[0].self_link
  }

  #allow for updates to the image family to happen without needing replacement on instance.
  lifecycle {
    ignore_changes = [metadata["windows-keys"]]
  }

  network_interface {
    subnetwork = var.app_subnet2_self_link
  }

  service_account {
    email  = var.windows_workstation_sa_email
    scopes = ["cloud-platform"]
  }

  guest_accelerator {
    count = 1
    type  = var.windows_gpu_type
  }

  shielded_instance_config {
    enable_secure_boot          = "false" #turn off for GPU
    enable_vtpm                 = "true"
    enable_integrity_monitoring = "true"
  }
}

##custom instance: eric braen to use a dependency included instant image
##note: this disk comes loaded with some of my user creds- don't hand to end user until these are scrubbed. Not a tight workflow at the moment.
resource "google_compute_instance" "eric_braen_pam_ww_ins" {
  count        = var.enable_custom_boot_disk_instance ? 1 : 0
  name         = "eric-braen-pam-ww-ins"
  machine_type = var.windows_machine_type
  project      = var.project_id
  zone         = var.zone1

  resource_policies = ["https://www.googleapis.com/compute/v1/projects/${var.project_id}/regions/${var.region1}/resourcePolicies/patch-boot-shutdown"]

  metadata = {
    block-project-ssh-keys = true
    enable-osconfig        = true
  }

  labels = {
    environment                     = var.environment
    noaa_fismaid                    = var.system_id
    noaa_lineoffice                 = var.lineoffice
    noaa_taskorder                  = var.taskorder
    noaa_environment                = var.environment
    noaa_applicationid              = var.application_id
    noaa_project_id                 = var.project_id
    windows_force_reboot_patch_15th = true
    product_name                    = "pam-ww"
  }

  boot_disk {
    source = var.windows_custom_boot_disk_source
  }

  #allow for updates to the image family to happen without needing replacement on instance.
  lifecycle {
    ignore_changes = [metadata["windows-keys"]]
  }

  network_interface {
    subnetwork = var.app_subnet2_self_link
  }

  service_account {
    email  = var.windows_workstation_sa_email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = "true"
    enable_vtpm                 = "true"
    enable_integrity_monitoring = "true"
  }
}
