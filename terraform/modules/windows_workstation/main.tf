data "google_compute_image" "latest_pam_ww" {
  family  = var.ww_image_family
  project = var.project_id
}

data "google_compute_image" "latest_pam_ww_template" {
  family  = var.ww_template_image_family
  project = var.project_id
}

data "google_compute_disk" "gpu_disk" {
  name    = var.gpu_disk_name
  zone    = var.zone
  project = var.project_id
}

locals {
  patch_policy_url = "https://www.googleapis.com/compute/v1/projects/${var.project_id}/regions/${var.region}/resourcePolicies/patch-boot-shutdown"
  ww_labels        = merge(var.common_labels, { product_name = "pam-ww" })
}

# ── Template instance ─────────────────────────────────────────────────────────
resource "google_compute_instance" "ww_template_instance" {
  name         = "latest-pam-ww-template-instance"
  machine_type = var.ww_machine_type
  project      = var.project_id
  zone         = var.zone

  resource_policies = [local.patch_policy_url]

  metadata = {
    block-project-ssh-keys = "true"
    enable-osconfig        = "true"
  }

  labels = merge(local.ww_labels, {
    windows_force_reboot_patch_15th = "true"
  })

  boot_disk {
    device_name = "latest-pam-ww-template-instance"
    initialize_params {
      image = data.google_compute_image.latest_pam_ww_template.name
      size  = var.ww_disk_size_gb
      type  = var.ww_disk_type
    }
  }

  lifecycle {
    ignore_changes = [metadata["windows-keys"]]
  }

  network_interface {
    subnetwork = var.app_subnet2_self_link
  }

  service_account {
    email  = var.ww_sa_email
    scopes = var.instance_scopes
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

# ── Per-user instances ────────────────────────────────────────────────────────
resource "google_compute_instance" "user_pam_ww" {
  for_each = toset(var.pam_ww_users)

  name         = "${lower(replace(replace(replace(each.value, "/[^a-z0-9]+/", "-"), "user-", ""), "noaa-gov-", ""))}-pam-ww"
  machine_type = var.ww_machine_type
  project      = var.project_id
  zone         = var.zone

  resource_policies = [local.patch_policy_url]

  metadata = {
    block-project-ssh-keys = "true"
    enable-osconfig        = "true"
  }

  labels = merge(local.ww_labels, {
    windows_force_reboot_patch_15th = "true"
  })

  boot_disk {
    device_name = "${lower(replace(replace(replace(each.value, "/[^a-z0-9]+/", "-"), "user-", ""), "noaa-gov-", ""))}-pam-ww"
    initialize_params {
      image = data.google_compute_image.latest_pam_ww.name
      size  = var.ww_disk_size_gb
      type  = var.ww_disk_type
    }
  }

  lifecycle {
    ignore_changes = [
      metadata["windows-keys"],
      boot_disk,
      machine_type,
      network_interface,
      labels["product_name"],
    ]
  }

  network_interface {
    subnetwork = var.app_subnet2_self_link
  }

  service_account {
    email  = var.ww_sa_email
    scopes = var.instance_scopes
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

# ── GPU instance ──────────────────────────────────────────────────────────────
resource "google_compute_instance" "gpu_instance" {
  name         = "dwoodrich-pam-ww-gpu2"
  machine_type = var.gpu_machine_type
  project      = var.project_id
  zone         = var.zone

  scheduling {
    on_host_maintenance = "TERMINATE"
  }

  resource_policies = [local.patch_policy_url]

  metadata = {
    block-project-ssh-keys = "true"
    enable-osconfig        = "true"
  }

  labels = merge(var.common_labels, {
    product_name                    = "pam-ww-gpu"
    windows_force_reboot_patch_15th = "true"
  })

  boot_disk {
    auto_delete = false
    source      = data.google_compute_disk.gpu_disk.self_link
  }

  lifecycle {
    ignore_changes = [metadata["windows-keys"]]
  }

  network_interface {
    subnetwork = var.app_subnet2_self_link
  }

  service_account {
    email  = var.ww_sa_email
    scopes = var.instance_scopes
  }

  guest_accelerator {
    count = 1
    type  = "https://www.googleapis.com/compute/v1/projects/${var.project_id}/zones/${var.zone}/acceleratorTypes/${var.gpu_accelerator_type}"
  }

  shielded_instance_config {
    enable_secure_boot          = false
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

# ── Eric Braen custom instance ────────────────────────────────────────────────
resource "google_compute_instance" "eric_braen_ww" {
  name         = "eric-braen-pam-ww-ins"
  machine_type = var.ww_machine_type
  project      = var.project_id
  zone         = var.zone

  resource_policies = [local.patch_policy_url]

  metadata = {
    block-project-ssh-keys = "true"
    enable-osconfig        = "true"
  }

  labels = merge(local.ww_labels, {
    windows_force_reboot_patch_15th = "true"
  })

  boot_disk {
    source = "projects/${var.project_id}/zones/${var.zone}/disks/${var.eric_braen_disk_name}"
  }

  lifecycle {
    ignore_changes = [metadata["windows-keys"]]
  }

  network_interface {
    subnetwork = var.app_subnet2_self_link
  }

  service_account {
    email  = var.ww_sa_email
    scopes = var.instance_scopes
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

# ── Eric Braen IAM ────────────────────────────────────────────────────────────
resource "google_storage_bucket_iam_member" "pam_ww_tmp_eric" {
  bucket   = "pam-ww-tmp-${var.project_id}"
  role     = "roles/storage.objectUser"
  for_each = toset(var.eric_braen_users)
  member   = each.key
}

resource "google_service_account_iam_member" "ww_sa_members_eric" {
  service_account_id = var.ww_sa_id
  role               = "roles/iam.serviceAccountUser"
  for_each           = toset(var.eric_braen_users)
  member             = each.key
}

resource "google_iap_tunnel_instance_iam_member" "ww_iap_tunnel_eric" {
  project  = var.project_id
  zone     = var.zone
  for_each = toset(var.eric_braen_users)
  instance = google_compute_instance.eric_braen_ww.name
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.key
}

resource "google_project_iam_member" "ww_compute_viewer_eric" {
  project  = var.project_id
  role     = "roles/compute.viewer"
  for_each = toset(var.eric_braen_users)
  member   = each.key
}

resource "google_compute_instance_iam_member" "pam_ww_login_eric" {
  for_each      = toset(var.eric_braen_users)
  zone          = var.zone
  project       = var.project_id
  instance_name = google_compute_instance.eric_braen_ww.name
  role          = var.compute_user_role_id
  member        = each.value
}
