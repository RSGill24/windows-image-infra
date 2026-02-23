#may be more of on a temporary basis...?

#for ost-1, session and tenant service accounts
#removed temporary sa (was getting tf errors that it was already deleted; assuming by the service, so just removed it from terraform).
#resource "google_storage_bucket_iam_member" "tau-sa-storage-admin-ost-1" {
#  bucket = google_storage_bucket.ost-1.name
#  role   = "roles/storage.admin"
#  for_each = toset([
#    "serviceAccount:ta-72-16ec-cebb@transfer-appliance-zimbru.iam.gserviceaccount.com",
#    "serviceAccount:project-1082594235851@storage-transfer-service.iam.gserviceaccount.com"
#  ])
#  member = each.key
#}

resource "google_storage_bucket_iam_member" "tau-sa-storage-admin-nefsc-1" {
  count  = var.enable_transfer_appliance_bindings ? 1 : 0
  bucket = var.transfer_appliance_target_bucket
  role   = "roles/storage.admin"
  member = var.transfer_appliance_member_1
}

resource "google_storage_bucket_iam_member" "tau-sa-storage-admin-nefsc-1-secondary" {
  count  = var.enable_transfer_appliance_bindings ? 1 : 0
  bucket = var.transfer_appliance_target_bucket
  role   = "roles/storage.admin"
  member = var.transfer_appliance_member_2
}

