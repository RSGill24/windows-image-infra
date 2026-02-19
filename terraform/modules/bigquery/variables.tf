variable "project_id" { type = string }
variable "compliance_dataset_id" { type = string }
variable "compliance_table_id" { type = string }
variable "gcs_logs_dataset_id" { type = string }
variable "compliance_description" {
  type    = string
  default = "BigQuery dataset for compliance data with dynamic quarterly artifact queries"
}

variable "compliance_table_schema" {
  type        = string
  description = "JSON schema for the compliance table"
}

variable "gcs_log_sink_filter" {
  type        = string
  description = "Filter for the GCS log sink"
}
