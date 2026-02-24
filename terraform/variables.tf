variable "environment" {
  type        = string
  description = "Deployment environment, e.g. dev/prod"
}

variable "project_id" {
  type        = string
  description = "GCP project id"
}

variable "region1" {
  type        = string
  description = "Primary region"
}

variable "zone1" {
  type        = string
  description = "Primary zone"
}

variable "application_id" {
  type        = string
  description = "Application id label"
}

variable "lineoffice" {
  type        = string
  description = "Line office label"
}

variable "system_id" {
  type        = string
  description = "System id label"
}

variable "taskorder" {
  type        = string
  description = "Task order label"
}

variable "bucket_prefix" {
  type        = string
  description = "Prefix used for bucket naming pattern"
}

variable "artifact_bucket" {
  type        = string
  description = "Artifact bucket used for generated metadata objects"
}

variable "auto_shutdown" {
  type        = bool
  description = "Enable auto shutdown behavior where applicable"
}

variable "enable_audit" {
  type        = bool
  description = "Enable audit specific resources and flows"
}

variable "cloudbuild_repo_uri" {
  type        = string
  description = "Source repo URI for cloud build trigger"
}

variable "cloudbuild_branch_ref" {
  type        = string
  description = "Branch ref for cloud build trigger"
}

variable "cloudbuild_schedule" {
  type        = string
  description = "Cron schedule for image rebuild"
}

variable "cloudbuild_time_zone" {
  type        = string
  description = "Time zone for scheduler"
}

variable "cloudbuild_filename" {
  type        = string
  description = "Cloudbuild yaml path in repo"
}

variable "cloudsql_psc_service_attachment" {
  type        = string
  description = "Service attachment URI for Cloud SQL PSC endpoint target"
}

variable "bq_compliance_dataset_id" {
  type        = string
  description = "BigQuery dataset id for compliance records"
}

variable "bq_compliance_table_id" {
  type        = string
  description = "BigQuery table id for compliance records"
}

variable "gcs_read_logs_dataset_id" {
  type        = string
  description = "BigQuery dataset id for GCS read logs"
}

variable "pamdata_admin" {
  type        = list(string)
  description = "Project admins"
}

variable "pamdata_supervisors" {
  type        = list(string)
  description = "Project supervisors"
}

variable "app_developers" {
  type        = list(string)
  description = "Application developers"
}

variable "pamdata_transfer_appliance_admins" {
  type        = list(string)
  description = "Transfer appliance admins"
}

variable "pamdata_transfer_appliance_users" {
  type        = list(string)
  description = "Transfer appliance users"
}

variable "nefsc_minke_detector_users" {
  type        = list(string)
  description = "Minke detector users"
}

variable "nefsc_humpback_detector_users" {
  type        = list(string)
  description = "Humpback detector users"
}

variable "afsc_instinct_users" {
  type        = list(string)
  description = "AFSC instinct users"
}

variable "bucket_users" {
  type        = list(string)
  description = "Users who can read data buckets"
}

variable "pam_ww_users1" {
  type        = list(string)
  description = "Windows workstation users list"
}

variable "data_buckets_map" {
  type = map(object({
    data_authority = string
    data_admins    = list(string)
    all_users      = list(string)
  }))
  description = "Central data bucket authority/admin/user mapping"
}

variable "windows_gpu_type" {
  type        = string
  description = "GPU accelerator type URI"
  default     = ""
}

variable "windows_custom_boot_disk_source" {
  type        = string
  description = "Custom boot disk source for special workstation"
  default     = ""
}

variable "ds_image_project_id" {
  type        = string
  description = "Project that hosts the Linux golden image family"
  default     = ""
}

variable "windows_workstation_image_project_id" {
  type        = string
  description = "Project that hosts the Windows workstation image family"
  default     = ""
}

variable "windows_template_image_project_id" {
  type        = string
  description = "Project that hosts the Windows template image family"
  default     = ""
}

variable "enable_gpu_workstation" {
  type        = bool
  description = "Enable the custom GPU workstation instance that boots from an existing disk"
  default     = false
}

variable "gpu_boot_disk_name" {
  type        = string
  description = "Existing disk name used as the boot disk when GPU workstation is enabled"
  default     = ""
}

variable "gpu_boot_disk_project_id" {
  type        = string
  description = "Project that hosts the existing GPU boot disk"
  default     = ""
}

variable "enable_custom_boot_disk_instance" {
  type        = bool
  description = "Enable the custom workstation instance that boots from windows_custom_boot_disk_source"
  default     = false
}

variable "enable_snapshot_disk_attachment" {
  type        = bool
  description = "Enable attaching the snapshot policy to snapshot_target_disk_name"
  default     = false
}

variable "windows_template_instance_name" {
  type        = string
  description = "Template instance name for workstation templates"
}

variable "windows_patch_schedule" {
  type        = string
  description = "Windows patch monthly cron"
}

variable "windows_patch_stop_schedule" {
  type        = string
  description = "Windows patch stop cron"
}

variable "linux_patch_schedule" {
  type        = string
  description = "Linux patch boot cron"
}
