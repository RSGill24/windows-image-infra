# ── Core Identity ─────────────────────────────────────────────────────────────
# No defaults here — must be explicitly set per environment in tfvars

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "Primary GCP region"
}

variable "zone" {
  type        = string
  description = "Primary GCP zone"
}

variable "environment" {
  type        = string
  description = "Deployment environment label (dev, prod)"
}

variable "application_id" {
  type        = string
  description = "Application ID used for labels and derived resource names"
}

variable "line_office" {
  type        = string
  description = "NOAA line office for resource labels"
}

variable "system_id" {
  type        = string
  description = "NOAA FISMA system ID for resource labels"
}

variable "task_order" {
  type        = string
  description = "NOAA task order number for resource labels"
}

# ── Networking ────────────────────────────────────────────────────────────────
# network_name, router_name, nat_name, subnet names
# are derived in locals.tf from network_prefix + environment
# DO NOT add network_name here

variable "network_prefix" {
  type        = string
  description = "Prefix for all network resource names. Combined with environment in locals.tf (e.g. app → app-network-prod)"
  default     = "app"
}

variable "app_subnet1_cidr" {
  type        = string
  description = "CIDR block for app-subnet1"
}

variable "app_subnet2_cidr" {
  type        = string
  description = "CIDR block for app-subnet2"
}

variable "db_subnet1_cidr" {
  type        = string
  description = "CIDR block for db-subnet1"
}

variable "batch_subnet_cidr" {
  type        = string
  description = "CIDR block for batch-subnet"
}

variable "iap_source_range" {
  type        = string
  description = "IAP TCP forwarding source netblock"
  default     = "35.235.240.0/20"
}

variable "cloud_router_asn" {
  type        = number
  description = "BGP ASN for the Cloud Router"
  default     = 64514
}

# ── IAM / Principals ──────────────────────────────────────────────────────────

variable "pamdata_admin" {
  type        = list(string)
  description = "Project-level admin principals"
}

variable "pamdata_supervisors" {
  type        = list(string)
  description = "Project supervisor principals"
}

variable "app_developers" {
  type        = list(string)
  description = "Application developer principals"
}

variable "transfer_appliance_admins" {
  type        = list(string)
  description = "Transfer appliance admin principals"
}

variable "transfer_appliance_users" {
  type        = list(string)
  description = "Transfer appliance user principals"
}

variable "nefsc_minke_detector_users" {
  type        = list(string)
  description = "NEFSC minke detector operator principals"
}

variable "nefsc_humpback_detector_users" {
  type        = list(string)
  description = "NEFSC humpback detector operator principals"
}

variable "afsc_instinct_users" {
  type        = list(string)
  description = "AFSC Instinct service operator principals"
}

# Replaces old hardcoded "bucket_users" variable.
# Only pass EXTRA users here (e.g. domain:noaa.gov).
# All project SA emails are auto-computed in locals.tf
# and merged into local.computed_bucket_users.
variable "extra_bucket_users" {
  type        = list(string)
  description = "Additional principals for bucket read access beyond auto-computed project SAs (e.g. domain:noaa.gov)"
  default     = []
}

variable "pam_ww_users" {
  type        = list(string)
  description = "User principals to provision individual Windows workstation instances for"
  default     = []
}

variable "eric_braen_users" {
  type        = list(string)
  description = "Principals granted access to Eric Braen custom instance"
  default     = ["user:eric.braen@noaa.gov"]
}

variable "transfer_appliance_service_accounts" {
  type        = list(string)
  description = "Service accounts granted storage.admin on the transfer appliance target bucket"
}

variable "transfer_appliance_target_bucket" {
  type        = string
  description = "GCS bucket name to grant transfer appliance service accounts access to"
  default     = "nefsc-1"
}

# ── Image Pipeline ────────────────────────────────────────────────────────────

variable "ww_image_family" {
  type        = string
  description = "Compute image family for user Windows workstation instances"
  default     = "pam-windows-workstation"
}

variable "ww_template_image_family" {
  type        = string
  description = "Compute image family for workstation template instance"
  default     = "pam-ww-templates"
}

variable "ds_image_family" {
  type        = string
  description = "Compute image family for data science / app dev server"
  default     = "pamdata-ds-gi"
}

variable "ww_machine_type" {
  type        = string
  description = "Machine type for standard Windows workstation instances"
  default     = "e2-standard-8"
}

variable "gpu_machine_type" {
  type        = string
  description = "Machine type for GPU workstation instance"
  default     = "n1-highmem-16"
}

variable "app_dev_machine_type" {
  type        = string
  description = "Machine type for the app dev / Docker server"
  default     = "e2-standard-4"
}

variable "ww_disk_size_gb" {
  type        = number
  description = "Boot disk size in GB for Windows workstation instances"
  default     = 250
}

variable "app_dev_disk_size_gb" {
  type        = number
  description = "Boot disk size in GB for the app dev server"
  default     = 360
}

variable "ww_disk_type" {
  type        = string
  description = "Boot disk type for all compute instances"
  default     = "pd-standard"
}

variable "gpu_accelerator_type" {
  type        = string
  description = "Short name of GPU accelerator type. Full URL is built in locals.tf"
  default     = "nvidia-tesla-t4"
}

variable "gpu_disk_name" {
  type        = string
  description = "Name of the existing persistent disk to attach to the GPU instance"
  default     = "dwoodrich-gpu3"
}

variable "eric_braen_disk_name" {
  type        = string
  description = "Name of the existing disk for Eric Braen's custom instance"
  default     = "ins-copy-eb"
}

variable "source_repo_name" {
  type        = string
  description = "Cloud Source Repository name. Full URL is built in locals.tf"
  default     = "tf-repo-pamdata"
}

variable "cloudbuild_config_file" {
  type        = string
  description = "Path to cloudbuild YAML file inside the source repo"
  default     = "packer/cloudbuild.yml"
}

variable "rebuild_schedule_cron" {
  type        = string
  description = "Cron expression for the monthly golden image rebuild"
  default     = "0 0 16 * *"
}

variable "packer_secret_id" {
  type        = string
  description = "Secret Manager secret ID containing the packer user password"
  default     = "packer_user_password"
}

variable "instance_scopes" {
  type        = list(string)
  description = "OAuth2 scopes attached to all compute instance service accounts"
  default     = ["https://www.googleapis.com/auth/cloud-platform"]
}

# ── Snapshot ──────────────────────────────────────────────────────────────────

variable "snapshot_policy_name" {
  type        = string
  description = "Name of the GPU disk snapshot resource policy"
  default     = "dwoodrich-gpu-snap-policy"
}

variable "snapshot_days_in_cycle" {
  type        = number
  description = "Snapshot frequency in days"
  default     = 1
}

variable "snapshot_start_time" {
  type        = string
  description = "UTC time to start daily snapshot (HH:MM format)"
  default     = "04:00"
}

variable "snapshot_max_retention_days" {
  type        = number
  description = "Maximum number of days to retain snapshots"
  default     = 14
}

# ── BigQuery ──────────────────────────────────────────────────────────────────

variable "compliance_dataset_id" {
  type        = string
  description = "BigQuery dataset ID for compliance data"
  default     = "pam_wv_instance_controls"
}

variable "compliance_table_id" {
  type        = string
  description = "BigQuery table ID for compliance records"
  default     = "pam-wv-instance-controls-table"
}

variable "gcs_logs_dataset_id" {
  type        = string
  description = "BigQuery dataset ID for GCS audit read logs"
  default     = "gcs_read_logs"
}

# ── Storage ───────────────────────────────────────────────────────────────────
# pam_ww_tmp_bucket name is derived in locals.tf from project_id
# DO NOT add it here

variable "data_buckets_map" {
  type = map(object({
    data_authority = string
    data_admins    = list(string)
    all_users      = list(string)
  }))
  description = "Map of data bucket names to their IAM configuration. Bucket names are keys."
}

# ── Patching ──────────────────────────────────────────────────────────────────

variable "ubuntu_patch_hour" {
  type        = number
  description = "UTC hour to run Ubuntu patch deployment"
  default     = 7
}

variable "ubuntu_patch_minute" {
  type        = number
  description = "UTC minute to run Ubuntu patch deployment"
  default     = 15
}

variable "ubuntu_patch_day" {
  type        = string
  description = "Day of week for Ubuntu patch deployment"
  default     = "WEDNESDAY"
}

variable "ubuntu_patch_duration" {
  type        = string
  description = "Max duration for Ubuntu patch window (e.g. 1800s)"
  default     = "1800s"
}

variable "windows_patch_hour" {
  type        = number
  description = "UTC hour to run Windows patch deployment"
  default     = 22
}

variable "windows_patch_minute" {
  type        = number
  description = "UTC minute to run Windows patch deployment"
  default     = 15
}

variable "windows_patch_month_day" {
  type        = number
  description = "Day of month for Windows monthly patch deployment"
  default     = 15
}

variable "windows_patch_duration" {
  type        = string
  description = "Max duration for Windows patch window (e.g. 5400s)"
  default     = "5400s"
}

variable "dormant_patch_boot_schedule" {
  type        = string
  description = "Cron schedule to boot dormant Linux instances for patching"
  default     = "0 7 * * 3"
}

variable "patch_boot_shutdown_start_schedule" {
  type        = string
  description = "Cron schedule to boot Windows instances for patch cycle"
  default     = "0 22 15 * *"
}

variable "patch_boot_shutdown_stop_schedule" {
  type        = string
  description = "Cron schedule to shut down Windows instances after patch cycle"
  default     = "59 23 15 * *"
}
