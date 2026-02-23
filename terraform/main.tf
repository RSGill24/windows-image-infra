module "apis" {
  source        = "./modules/apis"
  project_id    = local.cfg.project_id
  required_apis = local.required_apis
}

module "network" {
  source                      = "./modules/network"
  project_id                  = local.cfg.project_id
  region1                     = local.cfg.region1
  dns_policy_name             = local.network_defaults.dns_policy_name
  app_network_name            = local.network_defaults.app_network_name
  iap_ssh_firewall_name       = local.network_defaults.iap_ssh_firewall_name
  iap_rdp_firewall_name       = local.network_defaults.iap_rdp_firewall_name
  iap_winrm_firewall_name     = local.network_defaults.iap_winrm_firewall_name
  iap_source_ranges           = local.network_defaults.iap_source_ranges
  router_name                 = local.network_defaults.router_name
  nat_name                    = local.network_defaults.nat_name
  app_subnet1_name            = local.network_defaults.app_subnet1_name
  app_subnet1_cidr            = local.network_defaults.app_subnet1_cidr
  app_subnet2_name            = local.network_defaults.app_subnet2_name
  app_subnet2_cidr            = local.network_defaults.app_subnet2_cidr
  east_west_firewall_name     = local.network_defaults.east_west_firewall_name
  db_subnet1_name             = local.network_defaults.db_subnet1_name
  db_subnet1_cidr             = local.network_defaults.db_subnet1_cidr
  batch_subnet_name           = local.network_defaults.batch_subnet_name
  batch_subnet_cidr           = local.network_defaults.batch_subnet_cidr
  ubuntu_patch_day_of_week    = local.network_defaults.ubuntu_patch_day_of_week
  ubuntu_patch_hour           = local.network_defaults.ubuntu_patch_hour
  ubuntu_patch_minute         = local.network_defaults.ubuntu_patch_minute
  windows_patch_month_day     = local.network_defaults.windows_patch_month_day
  windows_patch_hour          = local.network_defaults.windows_patch_hour
  windows_patch_minute        = local.network_defaults.windows_patch_minute
  linux_patch_schedule        = local.cfg.linux_patch_schedule
  windows_patch_schedule      = local.cfg.windows_patch_schedule
  windows_patch_stop_schedule = local.cfg.windows_patch_stop_schedule
}

module "storage" {
  source                    = "./modules/storage"
  project_id                = local.cfg.project_id
  region1                   = local.cfg.region1
  zone1                     = local.cfg.zone1
  data_buckets_map          = var.data_buckets_map
  snapshot_policy_name      = local.storage_defaults.snapshot_policy_name
  snapshot_target_disk_name = local.storage_defaults.snapshot_target_disk_name
}

module "bigquery" {
  source                   = "./modules/bigquery"
  project_id               = local.cfg.project_id
  compliance_dataset_id    = local.cfg.bq_compliance_dataset_id
  compliance_table_id      = local.cfg.bq_compliance_table_id
  gcs_read_logs_dataset_id = local.cfg.gcs_read_logs_dataset_id
}

module "iam" {
  source                                  = "./modules/iam"
  project_id                              = local.cfg.project_id
  application_id                          = local.cfg.application_id
  zone1                                   = local.cfg.zone1
  pamdata_admin                           = var.pamdata_admin
  pamdata_supervisors                     = var.pamdata_supervisors
  app_developers                          = var.app_developers
  pamdata_transfer_appliance_admins       = var.pamdata_transfer_appliance_admins
  pamdata_transfer_appliance_users        = var.pamdata_transfer_appliance_users
  nefsc_minke_detector_users              = var.nefsc_minke_detector_users
  nefsc_humpback_detector_users           = var.nefsc_humpback_detector_users
  afsc_instinct_users                     = var.afsc_instinct_users
  bucket_users                            = var.bucket_users
  pam_ww_users1                           = var.pam_ww_users1
  data_buckets_map                        = var.data_buckets_map
  compliance_dataset_id                   = local.cfg.bq_compliance_dataset_id
  additional_source_readers               = local.iam_defaults.additional_source_readers
  standard_bucket_names                   = module.storage.standard_bucket_names
  windows_workstation_sa_account_id       = local.iam_defaults.windows_workstation_sa_account_id
  windows_workstation_sa_display_name     = local.iam_defaults.windows_workstation_sa_display_name
  app_dev_sa_account_id                   = local.iam_defaults.app_dev_sa_account_id
  app_dev_sa_display_name                 = local.iam_defaults.app_dev_sa_display_name
  nefsc_minke_detector_sa_account_id      = local.iam_defaults.nefsc_minke_detector_sa_account_id
  nefsc_minke_detector_sa_display_name    = local.iam_defaults.nefsc_minke_detector_sa_display_name
  nefsc_humpback_detector_sa_account_id   = local.iam_defaults.nefsc_humpback_detector_sa_account_id
  nefsc_humpback_detector_sa_display_name = local.iam_defaults.nefsc_humpback_detector_sa_display_name
  afsc_instinct_sa_account_id             = local.iam_defaults.afsc_instinct_sa_account_id
  afsc_instinct_sa_display_name           = local.iam_defaults.afsc_instinct_sa_display_name
  enable_transfer_appliance_bindings      = local.iam_defaults.enable_transfer_appliance_bindings
  transfer_appliance_target_bucket        = local.iam_defaults.transfer_appliance_target_bucket
  transfer_appliance_member_1             = local.iam_defaults.transfer_appliance_member_1
  transfer_appliance_member_2             = local.iam_defaults.transfer_appliance_member_2
}

module "application_development" {
  source                        = "./modules/application_development"
  project_id                    = local.cfg.project_id
  region1                       = local.cfg.region1
  zone1                         = local.cfg.zone1
  environment                   = var.environment
  application_id                = local.cfg.application_id
  lineoffice                    = local.cfg.lineoffice
  system_id                     = local.cfg.system_id
  taskorder                     = local.cfg.taskorder
  ds_image_family               = local.application_development_defaults.ds_image_family
  app_dev_instance_name         = local.application_development_defaults.app_dev_instance_name
  app_dev_machine_type          = local.application_development_defaults.app_dev_machine_type
  app_dev_boot_disk_size_gb     = local.application_development_defaults.app_dev_boot_disk_size_gb
  app_dev_boot_disk_type        = local.application_development_defaults.app_dev_boot_disk_type
  docker_repo_id                = local.application_development_defaults.docker_repo_id
  docker_repo_description       = local.application_development_defaults.docker_repo_description
  app_subnet1_self_link         = module.network.app_subnet1_self_link
  app_dev_service_account_email = module.iam.app_dev_sa_email
}

module "windows_workstation" {
  source                           = "./modules/windows_workstation"
  project_id                       = local.cfg.project_id
  region1                          = local.cfg.region1
  zone1                            = local.cfg.zone1
  environment                      = var.environment
  application_id                   = local.cfg.application_id
  lineoffice                       = local.cfg.lineoffice
  system_id                        = local.cfg.system_id
  taskorder                        = local.cfg.taskorder
  pam_ww_users1                    = var.pam_ww_users1
  windows_workstation_image_family = local.windows_defaults.windows_workstation_image_family
  windows_template_image_family    = local.windows_defaults.windows_template_image_family
  windows_machine_type             = local.windows_defaults.windows_machine_type
  windows_gpu_machine_type         = local.windows_defaults.windows_gpu_machine_type
  app_subnet2_self_link            = module.network.app_subnet2_self_link
  windows_workstation_sa_email     = module.iam.windows_workstation_sa_email
  windows_gpu_type                 = var.windows_gpu_type
  windows_custom_boot_disk_source  = var.windows_custom_boot_disk_source
}

module "sql" {
  source                          = "./modules/sql"
  project_id                      = local.cfg.project_id
  region1                         = local.cfg.region1
  zone1                           = local.cfg.zone1
  environment                     = var.environment
  application_id                  = local.cfg.application_id
  lineoffice                      = local.cfg.lineoffice
  system_id                       = local.cfg.system_id
  taskorder                       = local.cfg.taskorder
  cloudsql_psc_service_attachment = local.cfg.cloudsql_psc_service_attachment
  allowed_consumer_projects       = local.sql_defaults.allowed_consumer_projects
  app_network_id                  = module.network.app_network_id
  db_subnet1_id                   = module.network.db_subnet1_id
  psc_endpoint_ip_name            = local.sql_defaults.psc_endpoint_ip_name
  psc_forwarding_rule_name        = local.sql_defaults.psc_forwarding_rule_name
}

module "image_pipeline" {
  source                                      = "./modules/image_pipeline"
  project_id                                  = local.cfg.project_id
  region1                                     = local.cfg.region1
  pamdata_admin                               = var.pamdata_admin
  cloudbuild_repo_uri                         = local.cfg.cloudbuild_repo_uri
  cloudbuild_branch_ref                       = local.cfg.cloudbuild_branch_ref
  cloudbuild_filename                         = local.cfg.cloudbuild_filename
  cloudbuild_schedule                         = local.cfg.cloudbuild_schedule
  cloudbuild_time_zone                        = local.cfg.cloudbuild_time_zone
  cloudbuild_pubsub_topic_name                = local.image_pipeline_defaults.cloudbuild_pubsub_topic_name
  cloudbuild_trigger_name                     = local.image_pipeline_defaults.cloudbuild_trigger_name
  packer_builder_service_account_id           = local.image_pipeline_defaults.packer_builder_service_account_id
  packer_builder_service_account_display_name = local.image_pipeline_defaults.packer_builder_service_account_display_name
  packer_user_password_secret_id              = local.image_pipeline_defaults.packer_user_password_secret_id
  image_builder_role_id                       = module.iam.image_builder_role_id
}
