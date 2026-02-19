variable "project_id"            { type = string }
variable "compliance_dataset_id" { type = string }
variable "compliance_table_id"   { type = string }
variable "gcs_logs_dataset_id"   { type = string }
variable "config" {
  type = object({
    compliance_description  = string
    compliance_table_schema = string
    gcs_log_sink_filter     = string
  })
}
