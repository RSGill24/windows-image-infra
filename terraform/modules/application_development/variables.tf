variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region for resources"
}

variable "zone" {
  type        = string
  description = "GCP zone for compute instances"
}

variable "common_labels" {
  type        = map(string)
  description = "Common labels to apply to all resources"
  default     = {}
}

variable "ds_image_family" {
  type        = string
  description = "Compute image family for the data science / app dev server"
  default     = "pamdata-ds-gi"
}

variable "app_dev_machine_type" {
  type        = string
  description = "Machine type for the app dev server"
  default     = "e2-standard-4"
}

variable "app_dev_disk_size_gb" {
  type        = number
  description = "Boot disk size in GB for the app dev server"
  default     = 360
}

variable "app_dev_disk_type" {
  type        = string
  description = "Boot disk type for the app dev server"
  default     = "pd-standard"
}

variable "app_dev_sa_email" {
  type        = string
  description = "Service account email to attach to the app dev server instance"
}

variable "app_dev_sa_scopes" {
  type        = list(string)
  description = "OAuth scopes for the app dev server service account"
  default     = ["https://www.googleapis.com/auth/cloud-platform"]
}

variable "app_subnet1_self_link" {
  type        = string
  description = "Self-link of the subnet to attach the app dev server to"
}

variable "dormant_patch_boot_policy_url" {
  type        = string
  description = "Resource policy for dormant patch boot"
}

variable "instance_scopes" {
  type        = list(string)
  description = "Scopes for the instance service account"
  default     = ["cloud-platform"]
}
variable "docker_repo_id" {
  type        = string
  description = "Artifact Registry repository ID for Docker images"
  default     = "pamdata-docker-repo"
}
variable "resource_policies" {
  type        = list(string)
  description = "Resource policies to apply to the instance"
  default     = []
}

variable "labels" {
  type        = map(string)
  description = "Extra labels for the app dev server"
  default     = {}
}
