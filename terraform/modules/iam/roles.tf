resource "google_project_iam_custom_role" "tau_kms_user_role" {
  role_id     = "tau_kms_user_role"
  project     = var.project_id
  title       = "tau_kms_user_role"
  description = "Custom role for using the storage transfer appliance"
  permissions = [
    "iam.serviceAccounts.getIamPolicy",
    "resourcemanager.projects.getIamPolicy",
    "storage.buckets.getIamPolicy",
    "transferappliance.appliances.list",
    "transferappliance.orders.list",
    "transferappliance.orders.update",
    "transferappliance.appliances.get",
    "transferappliance.appliances.update",
    "transferappliance.credentials.get",
  ]
}

resource "google_project_iam_custom_role" "compute_user" {
  role_id     = "compute_user"
  project     = var.project_id
  title       = "compute_user"
  description = "Custom role for scientific users to modify instance state"
  permissions = [
    "compute.instances.start",
    "compute.instances.stop",
    "compute.instances.reset",
    "compute.instances.use",
    "compute.instances.osLogin",
  ]
}

resource "google_project_iam_custom_role" "bucket_lister" {
  role_id     = "bucket_lister"
  project     = var.project_id
  title       = "bucket_lister"
  description = "Custom role for listing buckets"
  permissions = ["storage.buckets.list"]
}

resource "google_project_iam_custom_role" "image_builder_role" {
  role_id     = "nmfs.${var.application_id}.image.builder.role"
  project     = var.project_id
  title       = "nmfs.${var.application_id}.image.builder.role"
  description = "Custom role for packer image builders"
  permissions = [
    "compute.disks.create",
    "compute.disks.delete",
    "compute.disks.useReadOnly",
    "compute.globalOperations.get",
    "compute.images.get",
    "compute.images.create",
    "compute.images.list",
    "compute.images.getFromFamily",
    "compute.images.deprecate",
    "compute.images.delete",
    "compute.images.useReadOnly",
    "compute.instances.create",
    "compute.instances.delete",
    "compute.instances.get",
    "compute.instances.setMetadata",
    "compute.instances.setServiceAccount",
    "compute.instances.stop",
    "compute.machineTypes.get",
    "compute.subnetworks.use",
    "compute.zoneOperations.get",
    "compute.zones.get",
    "compute.projects.get",
  ]
}

# Transfer appliance IAM
resource "google_storage_bucket_iam_member" "tau_sa_storage_admin_nefsc1" {
  bucket   = var.transfer_appliance_target_bucket
  role     = "roles/storage.admin"
  for_each = toset(var.transfer_appliance_service_accounts)
  member   = each.key
}
