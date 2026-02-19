variable "project_id" { type = string }
variable "region" { type = string }
variable "zone" { type = string }
variable "rebuild_schedule_cron" { type = string }

variable "cloudbuild_config_file" { type = string }
variable "packer_secret_id" { type = string }
variable "pamdata_admin" { type = list(string) }
variable "snapshot_policy_name" { type = string }
variable "snapshot_days_in_cycle" { type = number }
variable "snapshot_start_time" { type = string }
variable "snapshot_max_retention_days" { type = number }
variable "gpu_disk_name" { type = string }
variable "ubuntu_patch_hour" { type = number }
variable "ubuntu_patch_minute" { type = number }
variable "ubuntu_patch_day" { type = string }
variable "ubuntu_patch_duration" { type = string }
variable "windows_patch_hour" { type = number }
variable "windows_patch_minute" { type = number }
variable "windows_patch_month_day" { type = number }
variable "windows_patch_duration" { type = string }
variable "dormant_patch_boot_schedule" { type = string }
variable "patch_boot_shutdown_start_schedule" { type = string }
variable "patch_boot_shutdown_stop_schedule" { type = string }

variable "scheduler_job_name" { type = string }
variable "cloudbuild_trigger_name" { type = string }
variable "pubsub_topic_name" { type = string }
variable "packer_sa_account_id" { type = string }
variable "ubuntu_patch_id" { type = string }
variable "windows_patch_id" { type = string }
variable "source_repo_url" { type = string }
variable "scheduler_data" {
  type    = string
  default = "Run monthly build"
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
