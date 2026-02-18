locals {
  common_labels = {
    environment        = var.environment
    noaa_fismaid       = var.system_id
    noaa_lineoffice    = var.line_office
    noaa_taskorder     = var.task_order
    noaa_environment   = var.environment
    noaa_applicationid = var.application_id
    noaa_project_id    = var.project_id
  }
}

module "apis" {
  source     = "./modules/apis"
  project_id = var.project_id
}

module "network" {
  source            = "./modules/network"
  project_id        = var.project_id
  region            = var.region
  network_name      = var.network_name
  app_subnet1_cidr  = var.app_subnet1_cidr
  app_subnet2_cidr  = var.app_subnet2_cidr
  db_subnet1_cidr   = var.db_subnet1_cidr
  batch_subnet_cidr = var.batch_subnet_cidr
  iap_source_range  = var.iap_source_range
  cloud_router_asn  = var.cloud_router_asn
}

module "iam" {
  source                        = "./modules/iam"
  project_id                    = var.project_id
  application_id                = var.application_id
  pamdata_admin                 = var.pamdata_admin
  pamdata_supervisors           = var.pamdata_supervisors
  app_developers                = var.app_developers
  transfer_appliance_admins     = var.transfer_appliance_admins
  transfer_appliance_users      = var.transfer_appliance_users
  nefsc_minke_detector_users    = var.nefsc_minke_detector_users
  nefsc_humpback_detector_users = var.nefsc_humpback_detector_users
  afsc_instinct_users           = var.afsc_instinct_users
  bucket_users                  = var.bucket_users
  transfer_appliance_service_accounts  = var.transfer_appliance_service_accounts
  transfer_appliance_target_bucket     = var.transfer_appliance_target_bucket
}

module "storage" {
  source           = "./modules/storage"
  project_id       = var.project_id
  data_buckets_map = var.data_buckets_map
  bucket_users     = var.bucket_users
  depends_on       = [module.iam]
}

module "bigquery" {
  source               = "./modules/bigquery"
  project_id           = var.project_id
  compliance_dataset_id = var.compliance_dataset_id
  compliance_table_id  = var.compliance_table_id
  gcs_logs_dataset_id  = var.gcs_logs_dataset_id
}

module "image_pipeline" {
  source                 = "./modules/image_pipeline"
  project_id             = var.project_id
  region                 = var.region
  zone                   = var.zone
  rebuild_schedule_cron  = var.rebuild_schedule_cron
  source_repo_name       = var.source_repo_name
  cloudbuild_config_file = var.cloudbuild_config_file
  packer_secret_id       = var.packer_secret_id
  pamdata_admin          = var.pamdata_admin
  snapshot_policy_name        = var.snapshot_policy_name
  snapshot_days_in_cycle      = var.snapshot_days_in_cycle
  snapshot_start_time         = var.snapshot_start_time
  snapshot_max_retention_days = var.snapshot_max_retention_days
  gpu_disk_name               = var.gpu_disk_name
  ubuntu_patch_hour           = var.ubuntu_patch_hour
  ubuntu_patch_minute         = var.ubuntu_patch_minute
  ubuntu_patch_day            = var.ubuntu_patch_day
  ubuntu_patch_duration       = var.ubuntu_patch_duration
  windows_patch_hour          = var.windows_patch_hour
  windows_patch_minute        = var.windows_patch_minute
  windows_patch_month_day     = var.windows_patch_month_day
  windows_patch_duration      = var.windows_patch_duration
  dormant_patch_boot_schedule        = var.dormant_patch_boot_schedule
  patch_boot_shutdown_start_schedule = var.patch_boot_shutdown_start_schedule
  patch_boot_shutdown_stop_schedule  = var.patch_boot_shutdown_stop_schedule
}

module "windows_workstation" {
  source                 = "./modules/windows_workstation"
  project_id             = var.project_id
  region                 = var.region
  zone                   = var.zone
  common_labels          = local.common_labels
  ww_image_family        = var.ww_image_family
  ww_template_image_family = var.ww_template_image_family
  ww_machine_type        = var.ww_machine_type
  ww_disk_size_gb        = var.ww_disk_size_gb
  ww_disk_type           = var.ww_disk_type
  gpu_machine_type       = var.gpu_machine_type
  gpu_disk_name          = var.gpu_disk_name
  gpu_accelerator_type   = var.gpu_accelerator_type
  eric_braen_disk_name   = var.eric_braen_disk_name
  eric_braen_users       = var.eric_braen_users
  pam_ww_users           = var.pam_ww_users
  app_subnet2_self_link  = module.network.app_subnet2_self_link
  ww_sa_email            = module.iam.windows_workstation_sa_email
  ww_sa_id               = module.iam.windows_workstation_sa_id
  compute_user_role_id   = module.iam.compute_user_role_id
  depends_on             = [module.network, module.iam]
}

module "application_development" {
  source               = "./modules/application_development"
  project_id           = var.project_id
  region               = var.region
  zone                 = var.zone
  common_labels        = local.common_labels
  ds_image_family      = var.ds_image_family
  app_dev_machine_type = var.app_dev_machine_type
  app_dev_disk_size_gb = var.app_dev_disk_size_gb
  ww_disk_type         = var.ww_disk_type
  docker_repo_id       = var.docker_repo_id
  app_subnet1_self_link = module.network.app_subnet1_self_link
  app_dev_sa_email     = module.iam.app_dev_sa_email
  depends_on           = [module.network, module.iam]
}
