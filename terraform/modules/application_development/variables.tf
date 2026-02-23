variable "project_id" { type = string }
variable "region1" { type = string }
variable "zone1" { type = string }
variable "environment" { type = string }
variable "application_id" { type = string }
variable "lineoffice" { type = string }
variable "system_id" { type = string }
variable "taskorder" { type = string }

variable "ds_image_family" { type = string }
variable "app_dev_instance_name" { type = string }
variable "app_dev_machine_type" { type = string }
variable "app_dev_boot_disk_size_gb" { type = number }
variable "app_dev_boot_disk_type" { type = string }
variable "app_subnet1_self_link" { type = string }
variable "app_dev_service_account_email" { type = string }
variable "docker_repo_id" { type = string }
variable "docker_repo_description" { type = string }
