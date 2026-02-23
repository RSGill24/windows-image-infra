# Service accounts used across compute and pipeline modules.
resource "google_service_account" "windows_workstation_sa" {
  account_id   = var.windows_workstation_sa_account_id
  display_name = var.windows_workstation_sa_display_name
  project      = var.project_id
}

resource "google_service_account" "app_dev_sa" {
  account_id   = var.app_dev_sa_account_id
  display_name = var.app_dev_sa_display_name
  project      = var.project_id
}

resource "google_service_account" "nefsc_minke_detector" {
  account_id   = var.nefsc_minke_detector_sa_account_id
  display_name = var.nefsc_minke_detector_sa_display_name
  project      = var.project_id
}

resource "google_service_account" "nefsc_humpback_detector" {
  account_id   = var.nefsc_humpback_detector_sa_account_id
  display_name = var.nefsc_humpback_detector_sa_display_name
  project      = var.project_id
}

resource "google_service_account" "afsc_instinct" {
  account_id   = var.afsc_instinct_sa_account_id
  display_name = var.afsc_instinct_sa_display_name
  project      = var.project_id
}
