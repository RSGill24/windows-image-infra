variable "project_id" { type = string }
variable "region1" { type = string }
variable "pamdata_admin" { type = list(string) }

variable "cloudbuild_repo_uri" { type = string }
variable "cloudbuild_branch_ref" { type = string }
variable "cloudbuild_filename" { type = string }
variable "cloudbuild_schedule" { type = string }
variable "cloudbuild_time_zone" { type = string }
variable "cloudbuild_pubsub_topic_name" { type = string }
variable "cloudbuild_trigger_name" { type = string }
variable "packer_builder_service_account_id" { type = string }
variable "packer_builder_service_account_display_name" { type = string }
variable "packer_user_password_secret_id" { type = string }
variable "image_builder_role_id" { type = string }
