#big query dataset to append compliance data to- can then provide dynamic quarterly artifact with updated queries.
#
#this just loads in as string, then to query needs like:
#SELECT PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p',StartDate) FROM `ggn-nmfs-pamdata-prod-1.pam_wv_instance_controls.pam-wv-instance-controls-table` LIMIT 1000

resource "google_bigquery_dataset" "pam_wv_instance_controls" {
  project     = var.project_id
  dataset_id  = var.compliance_dataset_id
  description = "big query dataset to append compliance data to- can then provide dynamic quarterly artifact with updated queries."
}

resource "google_bigquery_table" "pam_wv_instance_controls_table" {
  dataset_id = google_bigquery_dataset.pam_wv_instance_controls.dataset_id
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

