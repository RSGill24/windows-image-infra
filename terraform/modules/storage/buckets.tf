resource "google_storage_bucket" "data_buckets" {
  for_each      = var.data_buckets_map
  name          = each.key
  project       = var.project_id
  location      = "US"
  force_destroy = false

  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "data_authority" {
  for_each = var.data_buckets_map
  bucket   = google_storage_bucket.data_buckets[each.key].name
  role     = "roles/storage.legacyBucketOwner"
  member   = each.value.data_authority
}

resource "google_storage_bucket_iam_member" "data_admins" {
  for_each = {
    for item in flatten([
      for bucket_name, bucket in var.data_buckets_map : [
        for admin in bucket.data_admins : {
          key         = "${bucket_name}-${admin}"
          bucket_name = bucket_name
          member      = admin
        }
      ]
    ]) : item.key => item
  }
  bucket = google_storage_bucket.data_buckets[each.value.bucket_name].name
  role   = "roles/storage.objectAdmin"
  member = each.value.member
}

resource "google_storage_bucket_iam_member" "bucket_all_users" {
  for_each = {
    for item in flatten([
      for bucket_name, bucket in var.data_buckets_map : [
        for user in bucket.all_users : {
          key         = "${bucket_name}-${user}"
          bucket_name = bucket_name
          member      = user
        }
      ]
    ]) : item.key => item
  }
  bucket = google_storage_bucket.data_buckets[each.value.bucket_name].name
  role   = "roles/storage.objectViewer"
  member = each.value.member
}

resource "google_storage_bucket_iam_member" "global_bucket_readers" {
  for_each = {
    for item in flatten([
      for bucket_name in keys(var.data_buckets_map) : [
        for user in var.bucket_users : {
          key         = "${bucket_name}-${user}"
          bucket_name = bucket_name
          member      = user
        }
      ]
    ]) : item.key => item
  }
  bucket = google_storage_bucket.data_buckets[each.value.bucket_name].name
  role   = "roles/storage.objectViewer"
  member = each.value.member
}

resource "google_storage_bucket" "pam_ww_tmp" {
  name          = "pam-ww-tmp-${var.project_id}"
  project       = var.project_id
  location      = "US"
  force_destroy = false
  uniform_bucket_level_access = true
}
