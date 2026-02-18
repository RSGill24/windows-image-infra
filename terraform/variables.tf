# ── Core Identity ────────────────────────────────────────────────────────────
variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "Primary GCP region"
  default     = "us-east4"
}

variable "zone" {
  type        = string
  description = "Primary GCP zone"
  default     = "us-east4-c"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, prod)"
  default     = "prod"
}

variable "application_id" {
  type        = string
  description = "Application ID for labels"
  default     = "pamdata"
}

variable "line_office" {
  type        = string
  description = "NOAA line office for labels"
  default     = "nmfs"
}

variable "system_id" {
  type        = string
  description = "NOAA FISMA system ID for labels"
  default     = "noaa4000"
}

variable "task_order" {
  type        = string
  description = "NOAA task order for labels"
  default     = "13051420fnffk0123"
}

# ── Backend ──────────────────────────────────────────────────────────────────
variable "tf_state_bucket" {
  type        = string
  description = "GCS bucket for Terraform state"
  default     = "tf-local-ggn-nmfs-pamdata-prod-1"
}

# ── IAM / Principals ─────────────────────────────────────────────────────────
variable "pamdata_admin" {
  type        = list(string)
  description = "Project-level admins"
  default = [
    "user:daniel.woodrich@noaa.gov",
    "user:jeffrey.walker@noaa.gov",
  ]
}

variable "pamdata_supervisors" {
  type        = list(string)
  description = "Project supervisors"
  default = [
    "user:sofie.vanparijs@noaa.gov",
    "user:rebecca.vanhoeck@noaa.gov",
  ]
}

variable "app_developers" {
  type        = list(string)
  description = "Application developer principals"
  default     = ["user:daniel.woodrich@noaa.gov"]
}

variable "transfer_appliance_admins" {
  type        = list(string)
  description = "Transfer appliance admin principals"
  default     = ["user:rebecca.vanhoeck@noaa.gov"]
}

variable "transfer_appliance_users" {
  type        = list(string)
  description = "Transfer appliance user principals"
  default = [
    "user:thomas.sejkora@noaa.gov",
    "user:daniel.woodrich@noaa.gov",
  ]
}

variable "nefsc_minke_detector_users" {
  type        = list(string)
  description = "NEFSC minke detector operators"
  default = [
    "user:daniel.woodrich@noaa.gov",
    "user:lindsey.transue@noaa.gov",
    "serviceAccount:composer-sa1@ggn-nmfs-pamarc-dev-1.iam.gserviceaccount.com",
  ]
}

variable "nefsc_humpback_detector_users" {
  type        = list(string)
  description = "NEFSC humpback detector operators"
  default = [
    "user:daniel.woodrich@noaa.gov",
    "user:lindsey.transue@noaa.gov",
    "serviceAccount:composer-sa1@ggn-nmfs-pamarc-dev-1.iam.gserviceaccount.com",
  ]
}

variable "afsc_instinct_users" {
  type        = list(string)
  description = "AFSC Instinct service operators"
  default = [
    "user:daniel.woodrich@noaa.gov",
    "serviceAccount:composer-sa1@ggn-nmfs-pamarc-dev-1.iam.gserviceaccount.com",
    "serviceAccount:afsc-instinct@ggn-nmfs-pamdata-prod-1.iam.gserviceaccount.com",
  ]
}

variable "bucket_users" {
  type        = list(string)
  description = "Principals that can read all data buckets"
  default = [
    "domain:noaa.gov",
    "serviceAccount:app-dev-sa@ggn-nmfs-pamdata-prod-1.iam.gserviceaccount.com",
    "serviceAccount:windows-workstation-sa@ggn-nmfs-pamdata-prod-1.iam.gserviceaccount.com",
    "serviceAccount:nefsc-minke-detector@ggn-nmfs-pamdata-prod-1.iam.gserviceaccount.com",
    "serviceAccount:nefsc-humpback-detector@ggn-nmfs-pamdata-prod-1.iam.gserviceaccount.com",
    "serviceAccount:composer-sa1@ggn-nmfs-pamarc-dev-1.iam.gserviceaccount.com",
    "serviceAccount:afsc-instinct@ggn-nmfs-pamdata-prod-1.iam.gserviceaccount.com",
    "serviceAccount:pamarc-run-sa@ggn-nmfs-pamarc-prod-1.iam.gserviceaccount.com",
  ]
}

variable "pam_ww_users" {
  type        = list(string)
  description = "Windows workstation user principals"
  default     = []
}

variable "eric_braen_users" {
  type        = list(string)
  description = "Eric Braen specific instance access principals"
  default     = ["user:eric.braen@noaa.gov"]
}

# ── Networking ───────────────────────────────────────────────────────────────
variable "network_name" {
  type    = string
  default = "app-network"
}

variable "app_subnet1_cidr" {
  type    = string
  default = "10.1.0.0/26"
}

variable "app_subnet2_cidr" {
  type    = string
  default = "10.1.0.64/26"
}

variable "db_subnet1_cidr" {
  type    = string
  default = "10.2.0.0/26"
}

variable "batch_subnet_cidr" {
  type    = string
  default = "10.3.0.0/16"
}

variable "iap_source_range" {
  type        = string
  description = "IAP TCP forwarding netblock"
  default     = "35.235.240.0/20"
}

variable "cloud_router_asn" {
  type    = number
  default = 64514
}

# ── Image Pipeline ───────────────────────────────────────────────────────────
variable "ww_image_family" {
  type        = string
  description = "Image family for user workstations"
  default     = "pam-windows-workstation"
}

variable "ww_template_image_family" {
  type        = string
  description = "Image family for workstation templates"
  default     = "pam-ww-templates"
}

variable "ds_image_family" {
  type        = string
  description = "Image family for data science / app dev server"
  default     = "pamdata-ds-gi"
}

variable "ww_machine_type" {
  type    = string
  default = "e2-standard-8"
}

variable "gpu_machine_type" {
  type    = string
  default = "n1-highmem-16"
}

variable "app_dev_machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "ww_disk_size_gb" {
  type    = number
  default = 250
}

variable "app_dev_disk_size_gb" {
  type    = number
  default = 360
}

variable "ww_disk_type" {
  type    = string
  default = "pd-standard"
}

variable "gpu_accelerator_type" {
  type        = string
  description = "Accelerator type URL for GPU instance"
  default     = "nvidia-tesla-t4"
}

variable "gpu_disk_name" {
  type        = string
  description = "Existing disk name for the GPU instance"
  default     = "dwoodrich-gpu3"
}

variable "eric_braen_disk_name" {
  type        = string
  description = "Existing disk name for Eric Braen custom instance"
  default     = "ins-copy-eb"
}

variable "source_repo_name" {
  type        = string
  description = "Cloud Source Repository name for CloudBuild trigger"
  default     = "tf-repo-pamdata"
}

variable "cloudbuild_config_file" {
  type        = string
  description = "Path to cloudbuild YAML inside the repo"
  default     = "packer/cloudbuild.yml"
}

variable "rebuild_schedule_cron" {
  type        = string
  description = "Cron schedule for the monthly image rebuild"
  default     = "0 0 16 * *"
}

variable "packer_secret_id" {
  type        = string
  description = "Secret Manager secret ID for packer user password"
  default     = "packer_user_password"
}

# ── Snapshot ──────────────────────────────────────────────────────────────────
variable "snapshot_policy_name" {
  type    = string
  default = "dwoodrich-gpu-snap-policy"
}

variable "snapshot_days_in_cycle" {
  type    = number
  default = 1
}

variable "snapshot_start_time" {
  type    = string
  default = "04:00"
}

variable "snapshot_max_retention_days" {
  type    = number
  default = 14
}

# ── BigQuery ──────────────────────────────────────────────────────────────────
variable "compliance_dataset_id" {
  type    = string
  default = "pam_wv_instance_controls"
}

variable "compliance_table_id" {
  type    = string
  default = "pam-wv-instance-controls-table"
}

variable "gcs_logs_dataset_id" {
  type    = string
  default = "gcs_read_logs"
}

# ── Storage ───────────────────────────────────────────────────────────────────
variable "data_buckets_map" {
  type = map(object({
    data_authority = string
    data_admins    = list(string)
    all_users      = list(string)
  }))
  description = "Map of data bucket names to their IAM configuration"
  default = {
    "omms-1" = {
      data_authority = "user:timothy.rowell@noaa.gov"
      data_admins = [
        "user:timothy.rowell@noaa.gov",
        "user:lindsey.peavey@noaa.gov",
        "user:eden.zangl@noaa.gov",
        "user:anastasia.kurz@noaa.gov",
        "user:samara.m.havern@noaa.gov",
        "user:emma.berretta@noaa.gov",
      ]
      all_users = []
    }
    "afsc-1" = {
      data_authority = "user:catherine.berchok@noaa.gov"
      data_admins = [
        "user:daniel.woodrich@noaa.gov",
        "user:catherine.berchok@noaa.gov",
      ]
      all_users = ["group:nmfs.afsc.nml.acoustics@noaa.gov"]
    }
    "nefsc-1" = {
      data_authority = "user:sofie.vanparijs@noaa.gov"
      data_admins = [
        "user:julianne.wilder@noaa.gov",
        "user:kate.choate@noaa.gov",
        "user:xavier.mouy@noaa.gov",
        "user:david.chevrier@noaa.gov",
        "user:timothy.rowell@noaa.gov",
        "user:taiki.sakai@noaa.gov",
        "user:catherine.dodge@noaa.gov",
      ]
      all_users = [
        "user:kate.choate@noaa.gov",
        "user:lindsey.transue@noaa.gov",
        "user:rebecca.vanhoek@noaa.gov",
        "user:irene.brinkman@noaa.gov",
        "user:rhett.finley@noaa.gov",
        "user:sofie.vanparijs@noaa.gov",
        "user:jeffrey.walker@noaa.gov",
        "user:jessica.mccormick@noaa.gov",
      ]
    }
    "sefsc-1" = {
      data_authority = "user:melissa.soldevilla@noaa.gov"
      data_admins = [
        "user:melissa.soldevilla@noaa.gov",
        "user:heloise.trouin-nouy@noaa.gov",
      ]
      all_users = [
        "group:nmfs.sefsc.mmt.pam-ecology@noaa.gov",
        "user:lia.caldwell@noaa.gov",
      ]
    }
    "afsc-2" = {
      data_authority = "user:timothy.rowell@noaa.gov"
      data_admins = [
        "user:timothy.rowell@noaa.gov",
        "user:matt.grossi@noaa.gov",
        "user:amelia.johnson@noaa.gov",
      ]
      all_users = []
    }
    "swfsc-1" = {
      data_authority = "user:shannon.rankin@noaa.gov"
      data_admins = [
        "user:kourtney.burger@noaa.gov",
        "user:shannon.rankin@noaa.gov",
      ]
      all_users = []
    }
    "nmfsc-1" = {
      data_authority = "user:marla.holt@noaa.gov"
      data_admins = [
        "user:marla.holt@noaa.gov",
        "user:candice.emmons@noaa.gov",
        "user:arial.brewer@noaa.gov",
      ]
      all_users = []
    }
    "nmfsc-2" = {
      data_authority = "user:candice.emmons@noaa.gov"
      data_admins = [
        "user:candice.emmons@noaa.gov",
        "user:marla.holt@noaa.gov",
        "user:arial.brewer@noaa.gov",
      ]
      all_users = []
    }
    "pifsc-1" = {
      data_authority = "user:ann.allen@noaa.gov"
      data_admins = [
        "user:jennifer.mccullough@noaa.gov",
        "user:ann.allen@noaa.gov",
        "user:karlina.berkness@noaa.gov",
        "user:selene.fregosi@noaa.gov",
        "user:jenny.trickey@noaa.gov",
      ]
      all_users = ["user:kourtney.burger@noaa.gov"]
    }
    "ost-1" = {
      data_authority = "user:jason.gedeon@noaa.gov"
      data_admins = [
        "user:samara.m.havern@noaa.gov",
        "user:lauren.k.rodgers@noaa.gov",
        "user:angela.treas@noaa.gov",
        "user:margi.swords@noaa.gov",
        "user:julianne.wilder@noaa.gov",
        "user:kate.choate@noaa.gov",
      ]
      all_users = ["user:samara.m.havern@noaa.gov"]
    }
    "pffs-collaborative" = {
      data_authority = ""
      data_admins    = ["group:nmfs.pam-gilders@noaa.gov"]
      all_users      = ["group:nmfs.pam-gilders@noaa.gov"]
    }
  }
}

variable "transfer_appliance_service_accounts" {
  type        = list(string)
  description = "Service accounts for the NEFSC-1 transfer appliance"
  default = [
    "serviceAccount:ta-c0-e326-9133@transfer-appliance-zimbru.iam.gserviceaccount.com",
    "serviceAccount:project-804870724004@storage-transfer-service.iam.gserviceaccount.com",
  ]
}

variable "transfer_appliance_target_bucket" {
  type        = string
  description = "Target bucket name for transfer appliance admin access"
  default     = "nefsc-1"
}

# ── Patching ──────────────────────────────────────────────────────────────────
variable "ubuntu_patch_hour" {
  type    = number
  default = 7
}

variable "ubuntu_patch_minute" {
  type    = number
  default = 15
}

variable "ubuntu_patch_day" {
  type    = string
  default = "WEDNESDAY"
}

variable "ubuntu_patch_duration" {
  type    = string
  default = "1800s"
}

variable "windows_patch_hour" {
  type    = number
  default = 22
}

variable "windows_patch_minute" {
  type    = number
  default = 15
}

variable "windows_patch_month_day" {
  type    = number
  default = 15
}

variable "windows_patch_duration" {
  type    = string
  default = "5400s"
}

variable "dormant_patch_boot_schedule" {
  type    = string
  default = "0 7 * * 3"
}

variable "patch_boot_shutdown_start_schedule" {
  type    = string
  default = "0 22 15 * *"
}

variable "patch_boot_shutdown_stop_schedule" {
  type    = string
  default = "59 23 15 * *"
}

# ── Docker / App Dev ─────────────────────────────────────────────────────────
variable "docker_repo_id" {
  type    = string
  default = "pamdata-docker-repo"
}
