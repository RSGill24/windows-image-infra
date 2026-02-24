variable "project_id" { type = string }
variable "application_id" { type = string }
variable "zone1" { type = string }
variable "aa_ncsi_service_account_member" {
  type    = string
  default = ""
}

variable "pamdata_admin" { type = list(string) }
variable "pamdata_supervisors" { type = list(string) }
variable "app_developers" { type = list(string) }
variable "pamdata_transfer_appliance_admins" { type = list(string) }
variable "pamdata_transfer_appliance_users" { type = list(string) }
variable "nefsc_minke_detector_users" { type = list(string) }
variable "nefsc_humpback_detector_users" { type = list(string) }
variable "afsc_instinct_users" { type = list(string) }
variable "bucket_users" { type = list(string) }
variable "pam_ww_users1" { type = list(string) }
variable "additional_source_readers" { type = list(string) }
variable "standard_bucket_names" { type = list(string) }
variable "named_bucket_names" { type = map(string) }

variable "data_buckets_map" {
  type = map(object({
    data_authority = string
    data_admins    = list(string)
    all_users      = list(string)
  }))
}

variable "compliance_dataset_id" { type = string }

variable "windows_workstation_sa_account_id" { type = string }
variable "windows_workstation_sa_display_name" { type = string }
variable "app_dev_sa_account_id" { type = string }
variable "app_dev_sa_display_name" { type = string }
variable "nefsc_minke_detector_sa_account_id" { type = string }
variable "nefsc_minke_detector_sa_display_name" { type = string }
variable "nefsc_humpback_detector_sa_account_id" { type = string }
variable "nefsc_humpback_detector_sa_display_name" { type = string }
variable "afsc_instinct_sa_account_id" { type = string }
variable "afsc_instinct_sa_display_name" { type = string }

variable "enable_transfer_appliance_bindings" { type = bool }
variable "transfer_appliance_target_bucket" { type = string }
variable "transfer_appliance_member_1" { type = string }
variable "transfer_appliance_member_2" { type = string }
# this is roles.tf file variable extra
variable "additional_source_repo_readers" {
  type    = list(string)
  default = []
}
variable "additional_bucket_objectviewer_buckets" {
  type    = list(string)
  default = []
}
variable "composer_service_account_member" {
  type    = string
  default = ""
}

variable "enable_pg_secret_bindings" {
  type    = bool
  default = false
}

variable "enable_taiki_secret_bindings" {
  type    = bool
  default = false
}
