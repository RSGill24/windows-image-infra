variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
}

variable "zone" {
  type        = string
  description = "GCP zone"
}

variable "common_labels" {
  type        = map(string)
  description = "Common labels applied to all instances"
  default     = {}
}

# ── Image families ────────────────────────────────────────────────────────────
variable "ww_image_family" {
  type        = string
  description = "Image family for user workstation instances"
  default     = "pam-windows-workstation"
}

variable "ww_template_image_family" {
  type        = string
  description = "Image family for workstation template instance"
  default     = "pam-ww-templates"
}

# ── Machine types ─────────────────────────────────────────────────────────────
variable "ww_machine_type" {
  type        = string
  description = "Machine type for standard windows workstation instances"
  default     = "e2-standard-8"
}

variable "gpu_machine_type" {
  type        = string
  description = "Machine type for GPU workstation instance"
  default     = "n1-highmem-16"
}

# ── Disk config ───────────────────────────────────────────────────────────────
variable "ww_disk_size_gb" {
  type        = number
  description = "Boot disk size in GB for windows workstation instances"
  default     = 250
}

variable "ww_disk_type" {
  type        = string
  description = "Boot disk type for windows workstation instances"
  default     = "pd-standard"
}

variable "gpu_disk_name" {
  type        = string
  description = "Name of the existing persistent disk for the GPU instance"
  default     = "dwoodrich-gpu3"
}

variable "gpu_accelerator_type" {
  type        = string
  description = "Short name of GPU accelerator type (e.g. nvidia-tesla-t4)"
  default     = "nvidia-tesla-t4"
}

variable "eric_braen_disk_name" {
  type        = string
  description = "Name of the existing disk for Eric Braen custom instance"
  default     = "ins-copy-eb"
}

# ── Networking ────────────────────────────────────────────────────────────────
variable "app_subnet2_self_link" {
  type        = string
  description = "Self link of app-subnet2 from the network module output"
}

# ── Service account ───────────────────────────────────────────────────────────
variable "ww_sa_email" {
  type        = string
  description = "Email of the windows workstation service account"
}

variable "ww_sa_id" {
  type        = string
  description = "Full resource ID of the windows workstation service account"
}

variable "instance_scopes" {
  type        = list(string)
  description = "OAuth2 scopes for all compute instance service accounts"
  default     = ["https://www.googleapis.com/auth/cloud-platform"]
}

# ── Users / IAM ───────────────────────────────────────────────────────────────
variable "pam_ww_users" {
  type        = list(string)
  description = "User principals to provision individual workstation instances for"
  default     = []
}

variable "eric_braen_users" {
  type        = list(string)
  description = "Principals granted access to Eric Braen's custom instance"
  default     = ["user:eric.braen@noaa.gov"]
}

variable "compute_user_role_id" {
  type        = string
  description = "ID of the compute_user custom IAM role from the iam module output"
}
variable "gpu_accelerator_url" {
  type        = string
  description = "Self-link to the accelerator type"
}

variable "pam_ww_tmp_bucket" {
  type        = string
  description = "Name of the temporary bucket for windows workstations"
}

variable "patch_policy_url" {
  type        = string
  description = "Self-link to the patch policy (resource policy) for instant snapshot/patching"
  default     = ""
}

variable "labels" {
  type        = map(string)
  description = "Extra labels for the windows workstation instances"
  default     = {}
}

variable "template_labels" {
  type        = map(string)
  description = "Labels specific to the template instance"
  default     = {}
}

variable "gpu_labels" {
  type        = map(string)
  description = "Labels specific to the GPU instance"
  default     = {}
}
