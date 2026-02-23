output "app_dev_sa_email" {
  value = google_service_account.app_dev_sa.email
}

output "windows_workstation_sa_email" {
  value = google_service_account.windows_workstation_sa.email
}

output "image_builder_role_id" {
  value = google_project_iam_custom_role.image_builder_role.id
}
