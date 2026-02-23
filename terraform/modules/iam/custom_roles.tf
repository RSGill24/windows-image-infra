#custom role for needed permissions to load data to appliance.
resource "google_project_iam_custom_role" "tau_kms_user_role" {
  role_id     = "tau_kms_user_role"
  project     = var.project_id
  title       = "tau_kms_user_role"
  description = "A custom role for using the storage transfer appliance"
  permissions = [
    "iam.serviceAccounts.getIamPolicy",
    "resourcemanager.projects.getIamPolicy",
    #"resourcemanager.projects.setIamPolicy", #even though it's requested, remove this as it seems highly overpermissioned. Fix is for me to just perform this step instead of tau
    "storage.buckets.getIamPolicy",
    #"storage.buckets.setIamPolicy", #even though it's requested, remove this as it seems highly overpermissioned. Fix is for me to just perform this step instead of tau
    "transferappliance.appliances.list",
    "transferappliance.orders.list",
    "transferappliance.orders.update",
    "transferappliance.appliances.get",
    "transferappliance.appliances.update",
    "transferappliance.credentials.get"
  ]
}

#custom role for compute instance state operation, to be bound at instance level.
resource "google_project_iam_custom_role" "compute_user" {
  role_id     = "compute_user"
  project     = var.project_id
  title       = "compute_user"
  description = "A Custom Role for scientific users of compute to modify state of instances and use an instance"
  permissions = [
    "compute.instances.start",
    "compute.instances.stop",
    "compute.instances.reset",
    "compute.instances.use",
    "compute.instances.osLogin"
  ]
}

#custom role for viewing data- object viewer + bucket listing.
resource "google_project_iam_custom_role" "bucket_lister" {
  role_id     = "bucket_lister"
  project     = var.project_id
  title       = "bucket_lister"
  description = "A custom role for listing buckets"
  permissions = [
    "storage.buckets.list"
  ]
}

#for cloudbuild packer service account
resource "google_project_iam_custom_role" "image_builder_role" {
  role_id     = "nmfs.${var.application_id}.image.builder.role"
  project     = var.project_id
  title       = "nmfs.${var.application_id}.image.builder.role"
  description = "A Custom Role for packer image builders"
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
    "compute.images.useReadOnly",
    "compute.images.delete"
  ]
}

