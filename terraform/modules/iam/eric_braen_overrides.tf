# Temporary Eric Braen-specific IAM bindings kept from legacy configuration.
locals {
  eric_braen_members = toset(["user:eric.braen@noaa.gov"])
}

resource "google_storage_bucket_iam_member" "pam_ww_tmp_object_admin_eric" {
  bucket   = var.named_bucket_names.pam_ww_tmp
  role     = "roles/storage.objectUser"
  for_each = local.eric_braen_members
  member   = each.key
}

resource "google_service_account_iam_member" "ww_sa_members_eric" {
  service_account_id = google_service_account.windows_workstation_sa.id
  role               = "roles/iam.serviceAccountUser"
  for_each           = local.eric_braen_members
  member             = each.key
}

resource "google_iap_tunnel_instance_iam_member" "ww_iap_tunnel_members_eric" {
  project  = var.project_id
  zone     = var.zone1
  for_each = local.eric_braen_members
  instance = "eric-braen-pam-ww-ins"
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.key
}

resource "google_project_iam_member" "ww_compute_viewers_eric" {
  project  = var.project_id
  role     = "roles/compute.viewer"
  for_each = local.eric_braen_members
  member   = each.key
}

resource "google_compute_instance_iam_member" "pam_ww_login_eric" {
  for_each = local.eric_braen_members

  zone          = var.zone1
  project       = var.project_id
  instance_name = "eric-braen-pam-ww-ins"
  role          = google_project_iam_custom_role.compute_user.id
  member        = each.value
}
