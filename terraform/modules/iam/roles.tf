resource "google_project_iam_custom_role" "tau_kms_user_role" {
  role_id     = "tau_kms_user_role"
  project     = var.project_id
  title       = "tau_kms_user_role"
  description = "Custom role for using the storage transfer appliance"
  permissions = var.config.tau_kms_user_permissions
}

resource "google_project_iam_custom_role" "compute_user" {
  role_id     = "compute_user"
  project     = var.project_id
  title       = "compute_user"
  description = "Custom role for scientific users to modify instance state"
  permissions = var.config.compute_user_permissions
}

resource "google_project_iam_custom_role" "bucket_lister" {
  role_id     = "bucket_lister"
  project     = var.project_id
  title       = "bucket_lister"
  description = "Custom role for listing buckets"
  permissions = var.config.bucket_lister_permissions
}

resource "google_project_iam_custom_role" "image_builder_role" {
  role_id     = "nmfs.${var.application_id}.image.builder.role"
  project     = var.project_id
  title       = "nmfs.${var.application_id}.image.builder.role"
  description = "Custom role for packer image builders"
  permissions = var.config.image_builder_permissions
}

# Transfer appliance IAM
resource "google_storage_bucket_iam_member" "tau_sa_storage_admin_nefsc1" {
  bucket   = var.transfer_appliance_target_bucket
  role     = "roles/storage.objectAdmin"
  for_each = toset(var.transfer_appliance_service_accounts)
  member   = each.key
}
