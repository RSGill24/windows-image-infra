variable "project_id" { type = string }
variable "region1" { type = string }
variable "zone1" { type = string }
variable "data_buckets_map" {
  type = map(object({
    data_authority = string
    data_admins    = list(string)
    all_users      = list(string)
  }))
}
variable "snapshot_policy_name" { type = string }
variable "snapshot_target_disk_name" { type = string }
