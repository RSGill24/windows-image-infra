variable "project_id" { type = string }
variable "region1" { type = string }
variable "zone1" { type = string }
variable "environment" { type = string }
variable "application_id" { type = string }
variable "lineoffice" { type = string }
variable "system_id" { type = string }
variable "taskorder" { type = string }
variable "bucket_prefix" { type = string }
variable "artifact_bucket" {
  type    = string
  default = ""
}
variable "data_buckets_map" {
  type = map(object({
    data_authority = string
    data_admins    = list(string)
    all_users      = list(string)
  }))
}
variable "snapshot_policy_name" { type = string }
variable "snapshot_target_disk_name" { type = string }
variable "enable_snapshot_disk_attachment" {
  type    = bool
  default = false
}
