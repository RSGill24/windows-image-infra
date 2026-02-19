variable "project_id"             { type = string }
variable "region"                 { type = string }
variable "zone"                   { type = string }
variable "rebuild_schedule_cron"  { type = string }
variable "source_repo_name"       { type = string }
variable "cloudbuild_config_file" { type = string }
variable "packer_secret_id"       { type = string }
variable "pamdata_admin"          { type = list(string) }
variable "snapshot_policy_name"        { type = string }
variable "snapshot_days_in_cycle"      { type = number }
variable "snapshot_start_time"         { type = string }
variable "snapshot_max_retention_days" { type = number }
variable "gpu_disk_name"               { type = string }
variable "ubuntu_patch_hour"           { type = number }
variable "ubuntu_patch_minute"         { type = number }
variable "ubuntu_patch_day"            { type = string }
variable "ubuntu_patch_duration"       { type = string }
variable "windows_patch_hour"          { type = number }
variable "windows_patch_minute"        { type = number }
variable "windows_patch_month_day"     { type = number }
variable "windows_patch_duration"      { type = string }
variable "dormant_patch_boot_schedule"        { type = string }
variable "patch_boot_shutdown_start_schedule" { type = string }
variable "patch_boot_shutdown_stop_schedule"  { type = string }
variable "config" {
  type = object({
    scheduler_data            = string
    image_builder_permissions = list(string)
  })
}
