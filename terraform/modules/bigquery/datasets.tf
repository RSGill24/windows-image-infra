resource "google_bigquery_dataset" "pam_wv_instance_controls" {
  dataset_id                 = var.compliance_dataset_id
  project                    = var.project_id
  description                = var.compliance_description
  delete_contents_on_destroy = true
}

resource "google_bigquery_table" "pam_wv_instance_controls_table" {
  dataset_id = google_bigquery_dataset.pam_wv_instance_controls.dataset_id
  project    = var.project_id
  table_id   = var.compliance_table_id

  schema = var.compliance_table_schema
}

# ── GCS Audit Logs Dataset ────────────────────────────────────────────────────
resource "google_project_iam_audit_config" "gcs_data_read" {
  project = var.project_id
  service = "storage.googleapis.com"
  audit_log_config {
    log_type = "DATA_READ"
  }
}

resource "google_bigquery_dataset" "logs" {
  dataset_id                 = var.gcs_logs_dataset_id
  project                    = var.project_id
  location                   = "US"
  delete_contents_on_destroy = true
}

resource "google_logging_project_sink" "gcs_reads_to_bq" {
  name                   = "gcs-reads-to-bq"
  project                = var.project_id
  destination            = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.logs.dataset_id}"
  filter                 = var.gcs_log_sink_filter
  unique_writer_identity = true
  depends_on             = [google_project_iam_audit_config.gcs_data_read]
  bigquery_options {
    use_partitioned_tables = true
  }
}

resource "google_bigquery_dataset_iam_member" "sink_writer" {
  dataset_id = google_bigquery_dataset.logs.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.gcs_reads_to_bq.writer_identity
}
