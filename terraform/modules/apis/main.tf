variable "project_id" { type = string }

locals {
  services = [
    "sourcerepo.googleapis.com",
    "transferappliance.googleapis.com",
    "artifactregistry.googleapis.com",
    "osconfig.googleapis.com",
    "secretmanager.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "iap.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
    "dns.googleapis.com",
  ]
}

resource "google_project_service" "enabled_apis" {
  for_each = toset(local.services)
  project  = var.project_id
  service  = each.value
}
