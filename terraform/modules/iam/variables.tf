variable "project_id" { type = string }
variable "application_id" { type = string }
variable "pamdata_admin" { type = list(string) }
variable "pamdata_supervisors" { type = list(string) }
variable "app_developers" { type = list(string) }
variable "transfer_appliance_admins" { type = list(string) }
variable "transfer_appliance_users" { type = list(string) }
variable "nefsc_minke_detector_users" { type = list(string) }
variable "nefsc_humpback_detector_users" { type = list(string) }
variable "afsc_instinct_users" { type = list(string) }
variable "bucket_users" { type = list(string) }
variable "transfer_appliance_service_accounts" { type = list(string) }
variable "transfer_appliance_target_bucket" { type = string }
variable "tau_kms_user_permissions" {
  type = list(string)
  default = [
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

variable "compute_user_permissions" {
  type = list(string)
  default = [
    "compute.instances.start",
    "compute.instances.stop",
    "compute.instances.reset",
    "compute.instances.use",
    "compute.instances.osLogin",
  ]
}

variable "bucket_lister_permissions" {
  type    = list(string)
  default = ["storage.buckets.list"]
}

variable "image_builder_permissions" {
  type = list(string)
  default = [
    "compute.disks.create", "compute.disks.delete", "compute.disks.useReadOnly",
    "compute.globalOperations.get", "compute.images.get", "compute.images.create",
    "compute.images.list", "compute.images.getFromFamily", "compute.images.deprecate",
    "compute.images.delete", "compute.images.useReadOnly",
    "compute.instances.create", "compute.instances.delete", "compute.instances.get",
    "compute.instances.setMetadata", "compute.instances.setServiceAccount",
    "compute.instances.stop", "compute.machineTypes.get", "compute.subnetworks.use",
    "compute.zoneOperations.get", "compute.zones.get", "compute.projects.get",
  ]
}
