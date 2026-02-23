output "packer_builder_service_account_email" {
  value = google_service_account.packer_builder_sa.email
}
