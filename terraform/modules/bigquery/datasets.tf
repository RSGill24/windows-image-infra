# ── Compliance Dataset ────────────────────────────────────────────────────────
resource "google_bigquery_dataset" "pam_wv_instance_controls" {
  dataset_id                 = var.compliance_dataset_id
  project                    = var.project_id
  description                = "BigQuery dataset for compliance data with dynamic quarterly artifact queries"
  delete_contents_on_destroy = true
}

resource "google_bigquery_table" "pam_wv_instance_controls_table" {
  dataset_id = google_bigquery_dataset.pam_wv_instance_controls.dataset_id
  project    = var.project_id
  table_id   = var.compliance_table_id

  schema = <<EOF
[
  {"name":"ConfigurationName","type":"STRING"},
  {"name":"DependsOn","type":"STRING"},
  {"name":"ModuleName","type":"STRING"},
  {"name":"ModuleVersion","type":"STRING"},
  {"name":"PsDscRunAsCredential","type":"STRING"},
  {"name":"ResourceId","type":"STRING"},
  {"name":"SourceInfo","type":"STRING"},
  {"name":"DurationInSeconds","type":"FLOAT64"},
  {"name":"Error","type":"STRING"},
  {"name":"FinalState","type":"STRING"},
  {"name":"InDesiredState","type":"BOOL"},
  {"name":"InitialState","type":"STRING"},
  {"name":"InstanceName","type":"STRING"},
  {"name":"RebootRequested","type":"BOOL"},
  {"name":"ResourceName","type":"STRING"},
  {"name":"StartDate","type":"STRING"},
  {"name":"StateChanged","type":"BOOL"},
  {"name":"PSComputerName","type":"STRING"},
  {"name":"CimClass","type":"STRING"},
  {"name":"CimInstanceProperties","type":"STRING"},
  {"name":"CimSystemProperties","type":"STRING"},
  {"name":"Compliance","type":"BOOL"},
  {"name":"GCPInstanceName","type":"STRING"},
  {"name":"GCPInstanceId","type":"INT64"},
  {"name":"GCPImageName","type":"STRING"},
  {"name":"GCPAuditUuid","type":"STRING"}
]
EOF
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
  name        = "gcs-reads-to-bq"
  project     = var.project_id
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.logs.dataset_id}"
  filter      = <<-EOT
    logName="projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Fdata_access"
    resource.type = "gcs_bucket"
    protoPayload.serviceName="storage.googleapis.com"
    protoPayload.methodName=("storage.objects.get|storage.objects.getRange|storage.objects.compose|storage.objects.rewrite|storage.objects.copy")
  EOT
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
