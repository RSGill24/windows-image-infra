variable "project_id"                         { type = string }
variable "application_id"                     { type = string }
variable "pamdata_admin"                       { type = list(string) }
variable "pamdata_supervisors"                 { type = list(string) }
variable "app_developers"                      { type = list(string) }
variable "transfer_appliance_admins"           { type = list(string) }
variable "transfer_appliance_users"            { type = list(string) }
variable "nefsc_minke_detector_users"          { type = list(string) }
variable "nefsc_humpback_detector_users"       { type = list(string) }
variable "afsc_instinct_users"                 { type = list(string) }
variable "bucket_users"                        { type = list(string) }
variable "transfer_appliance_service_accounts" { type = list(string) }
variable "transfer_appliance_target_bucket"    { type = string }
variable "config" {
  type = object({
    tau_kms_user_permissions  = list(string)
    compute_user_permissions  = list(string)
    bucket_lister_permissions = list(string)
    image_builder_permissions = list(string)
  })
}
