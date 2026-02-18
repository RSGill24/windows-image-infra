variable "project_id" { type = string }
variable "bucket_users" { type = list(string) }
variable "data_buckets_map" {
  type = map(object({
    data_authority = string
    data_admins    = list(string)
    all_users      = list(string)
  }))
}
