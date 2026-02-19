module "apis" {
  source     = "./modules/apis"
  project_id = var.project_id
  services = [
    "sourcerepo.googleapis.com",
    "transferappliance.googleapis.com",
    "artifactregistry.googleapis.com",
    "osconfig.googleapis.com",
    "secretmanager.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "iap.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
    "dns.googleapis.com",
  ]
}

module "network" {
  source     = "./modules/network"
  project_id = var.project_id
  region     = var.region

  # ── Names from locals (environment-aware) ──────────────────────────────────
  network_name = local.network_name
  router_name  = local.router_name
  nat_name     = local.nat_name
  subnet_app1  = local.subnet_app1
  subnet_app2  = local.subnet_app2
  subnet_db1   = local.subnet_db1
  subnet_batch = local.subnet_batch

  # ── CIDRs and network config from vars ────────────────────────────────────
  app_subnet1_cidr  = var.app_subnet1_cidr
  app_subnet2_cidr  = var.app_subnet2_cidr
  db_subnet1_cidr   = var.db_subnet1_cidr
  batch_subnet_cidr = var.batch_subnet_cidr
  iap_source_range  = var.iap_source_range
  cloud_router_asn  = var.cloud_router_asn
}

module "iam" {
  source         = "./modules/iam"
  project_id     = var.project_id
  application_id = var.application_id

  # ── Principals from vars ──────────────────────────────────────────────────
  pamdata_admin                 = var.pamdata_admin
  pamdata_supervisors           = var.pamdata_supervisors
  app_developers                = var.app_developers
  transfer_appliance_admins     = var.transfer_appliance_admins
  transfer_appliance_users      = var.transfer_appliance_users
  nefsc_minke_detector_users    = var.nefsc_minke_detector_users
  nefsc_humpback_detector_users = var.nefsc_humpback_detector_users
  afsc_instinct_users           = var.afsc_instinct_users

  # ── Bucket users from local (computed, includes all project SAs) ──────────
  bucket_users = local.computed_bucket_users

  # ── Transfer appliance ────────────────────────────────────────────────────
  transfer_appliance_service_accounts = var.transfer_appliance_service_accounts
  transfer_appliance_target_bucket    = var.transfer_appliance_target_bucket
}

module "storage" {
  source           = "./modules/storage"
  project_id       = var.project_id
  data_buckets_map = var.data_buckets_map

  # ── Use computed bucket users from local ──────────────────────────────────
  bucket_users = local.computed_bucket_users

  # ── Bucket name from local (includes project_id) ─────────────────────────
  pam_ww_tmp_bucket = local.pam_ww_tmp_bucket

  depends_on = [module.iam]
}

module "bigquery" {
  source                  = "./modules/bigquery"
  project_id              = var.project_id
  compliance_dataset_id   = var.compliance_dataset_id
  compliance_table_id     = var.compliance_table_id
  gcs_logs_dataset_id     = var.gcs_logs_dataset_id
  compliance_description  = var.compliance_description
  compliance_table_schema = var.compliance_table_schema
  gcs_log_sink_filter     = var.gcs_log_sink_filter
}

module "image_pipeline" {
  source     = "./modules/image_pipeline"
  project_id = var.project_id
  region     = var.region
  zone       = var.zone

  # ── Names from locals (environment-aware) ──────────────────────────────────
  scheduler_job_name      = local.scheduler_job_name
  cloudbuild_trigger_name = local.cloudbuild_trigger_name
  pubsub_topic_name       = local.pubsub_topic_name
  packer_sa_account_id    = local.packer_sa_account_id
  ubuntu_patch_id         = local.ubuntu_patch_deployment_id
  windows_patch_id        = local.windows_patch_deployment_id

  # ── Source repo URL from local (built from project_id + repo name) ────────
  source_repo_url        = local.source_repo_url
  cloudbuild_config_file = var.cloudbuild_config_file
  rebuild_schedule_cron  = var.rebuild_schedule_cron
  packer_secret_id       = var.packer_secret_id
  pamdata_admin          = var.pamdata_admin

  # ── Snapshot ──────────────────────────────────────────────────────────────
  snapshot_policy_name        = var.snapshot_policy_name
  snapshot_days_in_cycle      = var.snapshot_days_in_cycle
  snapshot_start_time         = var.snapshot_start_time
  snapshot_max_retention_days = var.snapshot_max_retention_days
  gpu_disk_name               = var.gpu_disk_name

  # ── Patching ──────────────────────────────────────────────────────────────
  ubuntu_patch_hour                  = var.ubuntu_patch_hour
  ubuntu_patch_minute                = var.ubuntu_patch_minute
  ubuntu_patch_day                   = var.ubuntu_patch_day
  ubuntu_patch_duration              = var.ubuntu_patch_duration
  windows_patch_hour                 = var.windows_patch_hour
  windows_patch_minute               = var.windows_patch_minute
  windows_patch_month_day            = var.windows_patch_month_day
  windows_patch_duration             = var.windows_patch_duration
  dormant_patch_boot_schedule        = var.dormant_patch_boot_schedule
  patch_boot_shutdown_start_schedule = var.patch_boot_shutdown_start_schedule
  patch_boot_shutdown_stop_schedule  = var.patch_boot_shutdown_stop_schedule
}

module "windows_workstation" {
  source     = "./modules/windows_workstation"
  project_id = var.project_id
  region     = var.region
  zone       = var.zone

  # ── Labels from local ─────────────────────────────────────────────────────
  common_labels = local.common_labels

  # ── Resource policy URLs from local (built from project_id + region) ──────
  patch_policy_url = local.patch_boot_shutdown_policy_url

  # ── GPU accelerator full URL from local ───────────────────────────────────
  gpu_accelerator_url = local.gpu_accelerator_url

  # ── Tmp bucket name from local ────────────────────────────────────────────
  pam_ww_tmp_bucket = local.pam_ww_tmp_bucket

  # ── Image and machine config from vars ────────────────────────────────────
  ww_image_family          = var.ww_image_family
  ww_template_image_family = var.ww_template_image_family
  ww_machine_type          = var.ww_machine_type
  ww_disk_size_gb          = var.ww_disk_size_gb
  ww_disk_type             = var.ww_disk_type
  gpu_machine_type         = var.gpu_machine_type
  gpu_disk_name            = var.gpu_disk_name
  eric_braen_disk_name     = var.eric_braen_disk_name
  instance_scopes          = var.instance_scopes

  # ── Users from vars ───────────────────────────────────────────────────────
  pam_ww_users     = var.pam_ww_users
  eric_braen_users = var.eric_braen_users

  # ── Networking from network module output ─────────────────────────────────
  app_subnet2_self_link = module.network.app_subnet2_self_link

  # ── SA email from local (computed), SA ID from iam module output ──────────
  ww_sa_email          = local.ww_sa_email
  ww_sa_id             = module.iam.windows_workstation_sa_id
  compute_user_role_id = module.iam.compute_user_role_id

  depends_on = [module.network, module.iam]
}

module "application_development" {
  source     = "./modules/application_development"
  project_id = var.project_id
  region     = var.region
  zone       = var.zone

  # ── Labels from local ─────────────────────────────────────────────────────
  common_labels = local.common_labels

  # ── Resource policy URL from local ────────────────────────────────────────
  dormant_patch_boot_policy_url = local.dormant_patch_boot_policy_url

  # ── Docker repo ID from local (built from application_id) ─────────────────
  docker_repo_id = local.docker_repo_id

  # ── Image and machine config from vars ────────────────────────────────────
  ds_image_family      = var.ds_image_family
  app_dev_machine_type = var.app_dev_machine_type
  app_dev_disk_size_gb = var.app_dev_disk_size_gb
  app_dev_disk_type    = var.ww_disk_type
  instance_scopes      = var.instance_scopes

  # ── Networking from network module output ─────────────────────────────────
  app_subnet1_self_link = module.network.app_subnet1_self_link

  # ── SA email from local (computed) ────────────────────────────────────────
  app_dev_sa_email = local.app_dev_sa_email

  depends_on = [module.network, module.iam]
}
