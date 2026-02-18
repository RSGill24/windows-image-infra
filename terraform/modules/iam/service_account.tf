resource "google_service_account" "windows_workstation_sa" {
  account_id   = "windows-workstation-sa"
  display_name = "Service account for windows workstation users"
  project      = var.project_id
}

resource "google_service_account" "app_dev_sa" {
  account_id   = "app-dev-sa"
  display_name = "Service account for application developers principle group"
  project      = var.project_id
}

resource "google_service_account" "nefsc_minke_detector" {
  account_id   = "nefsc-minke-detector"
  display_name = "Service account for the nefsc minke detector"
  project      = var.project_id
}

resource "google_service_account" "nefsc_humpback_detector" {
  account_id   = "nefsc-humpback-detector"
  display_name = "Service account for the nefsc humpback detector"
  project      = var.project_id
}

resource "google_service_account" "afsc_instinct" {
  account_id   = "afsc-instinct"
  display_name = "Service account for afsc instinct"
  project      = var.project_id
}
