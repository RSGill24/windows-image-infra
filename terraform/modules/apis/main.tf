variable "project_id" { type = string }

variable "services" {
  type        = list(string)
  description = "List of Google Cloud APIs to enable"
}

resource "google_project_service" "enabled_apis" {
  for_each = toset(var.services)
  project  = var.project_id
  service  = each.value
}
