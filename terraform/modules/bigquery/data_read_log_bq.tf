resource "google_project_iam_audit_config" "gcs_data_read" {
  project = var.project_id
  service = "storage.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }
}

resource "google_bigquery_dataset" "logs" {
  project                    = var.project_id
  dataset_id                 = var.gcs_read_logs_dataset_id
  location                   = "US"
  delete_contents_on_destroy = true
}

# cover all access events
resource "google_logging_project_sink" "gcs_reads_to_bq" {
  name        = "gcs-reads-to-bq"
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.logs.dataset_id}"
  filter      = <<-EOT
logName="projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Fdata_access"
resource.type = "gcs_bucket"
protoPayload.serviceName="storage.googleapis.com"
protoPayload.methodName=("storage.objects.get|storage.objects.getRange|storage.objects.compose|storage.objects.rewrite|storage.objects.copy")
EOT

  unique_writer_identity = true

  depends_on = [google_project_iam_audit_config.gcs_data_read]

  bigquery_options {
    use_partitioned_tables = true
  }
}

resource "google_bigquery_dataset_iam_member" "sink_writer" {
  dataset_id = google_bigquery_dataset.logs.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.gcs_reads_to_bq.writer_identity
}

