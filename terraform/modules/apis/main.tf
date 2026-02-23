locals {
  required_apis = toset(var.required_apis)
}

resource "google_project_service" "required" {
  for_each = local.required_apis

  project = var.project_id
  service = each.value
}
