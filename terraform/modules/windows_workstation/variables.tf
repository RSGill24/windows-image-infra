variable "project_id" { type = string }
variable "region1" { type = string }
variable "zone1" { type = string }
variable "environment" { type = string }
variable "application_id" { type = string }
variable "lineoffice" { type = string }
variable "system_id" { type = string }
variable "taskorder" { type = string }
variable "pam_ww_users1" { type = list(string) }

variable "windows_workstation_image_family" { type = string }
variable "windows_template_image_family" { type = string }
variable "windows_machine_type" { type = string }
variable "windows_gpu_machine_type" { type = string }
variable "app_subnet2_self_link" { type = string }
variable "windows_workstation_sa_email" { type = string }
variable "windows_gpu_type" { type = string }
variable "windows_custom_boot_disk_source" { type = string }
