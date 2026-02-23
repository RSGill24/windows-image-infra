locals {
  defaults_by_env = {
    dev = {
      project_id                     = "ggn-nmfs-pamdata-dev-1"
      region1                        = "us-east4"
      zone1                          = "us-east4-c"
      application_id                 = "pamdata"
      lineoffice                     = "nmfs"
      system_id                      = "noaa4000"
      taskorder                      = "13051420fnffk0123"
      cloudbuild_branch_ref          = "refs/heads/main"
      cloudbuild_schedule            = "0 0 16 * *"
      cloudbuild_time_zone           = "Etc/UTC"
      cloudbuild_filename            = "packer/cloudbuild.yml"
      bq_compliance_dataset_id       = "pam_wv_instance_controls"
      bq_compliance_table_id         = "pam-wv-instance-controls-table"
      gcs_read_logs_dataset_id       = "gcs_read_logs"
      windows_template_instance_name = "lastest-pam-ww-template-instance"
      windows_patch_schedule         = "0 22 15 * *"
      windows_patch_stop_schedule    = "59 23 15 * *"
      linux_patch_schedule           = "0 7 * * 3"
    }
    prod = {
      project_id                     = "ggn-nmfs-pamdata-prod-1"
      region1                        = "us-east4"
      zone1                          = "us-east4-c"
      application_id                 = "pamdata"
      lineoffice                     = "nmfs"
      system_id                      = "noaa4000"
      taskorder                      = "13051420fnffk0123"
      cloudbuild_branch_ref          = "refs/heads/master"
      cloudbuild_schedule            = "0 0 16 * *"
      cloudbuild_time_zone           = "Etc/UTC"
      cloudbuild_filename            = "packer/cloudbuild.yml"
      bq_compliance_dataset_id       = "pam_wv_instance_controls"
      bq_compliance_table_id         = "pam-wv-instance-controls-table"
      gcs_read_logs_dataset_id       = "gcs_read_logs"
      windows_template_instance_name = "lastest-pam-ww-template-instance"
      windows_patch_schedule         = "0 22 15 * *"
      windows_patch_stop_schedule    = "59 23 15 * *"
      linux_patch_schedule           = "0 7 * * 3"
    }
  }

  env_defaults = local.defaults_by_env[var.environment]

  cfg = {
    project_id                      = var.project_id
    region1                         = var.region1
    zone1                           = var.zone1
    application_id                  = var.application_id
    lineoffice                      = var.lineoffice
    system_id                       = var.system_id
    taskorder                       = var.taskorder
    cloudbuild_repo_uri             = var.cloudbuild_repo_uri
    cloudbuild_branch_ref           = var.cloudbuild_branch_ref
    cloudbuild_schedule             = var.cloudbuild_schedule
    cloudbuild_time_zone            = var.cloudbuild_time_zone
    cloudbuild_filename             = var.cloudbuild_filename
    cloudsql_psc_service_attachment = var.cloudsql_psc_service_attachment
    bq_compliance_dataset_id        = var.bq_compliance_dataset_id
    bq_compliance_table_id          = var.bq_compliance_table_id
    gcs_read_logs_dataset_id        = var.gcs_read_logs_dataset_id
    windows_template_instance_name  = var.windows_template_instance_name
    windows_patch_schedule          = var.windows_patch_schedule
    windows_patch_stop_schedule     = var.windows_patch_stop_schedule
    linux_patch_schedule            = var.linux_patch_schedule
    auto_shutdown                   = var.auto_shutdown
    enable_audit                    = var.enable_audit
  }

  required_apis = [
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

  network_defaults = {
    dns_policy_name          = "dns-logging"
    app_network_name         = "app-network"
    iap_ssh_firewall_name    = "ingress-allow-iap-to-ssh"
    iap_rdp_firewall_name    = "ingress-allow-iap-to-rdp"
    iap_winrm_firewall_name  = "ingress-allow-iap-to-winrm-ssl"
    iap_source_ranges        = ["35.235.240.0/20"]
    router_name              = "app-router"
    nat_name                 = "app-nat"
    app_subnet1_name         = "app-subnet1"
    app_subnet1_cidr         = "10.1.0.0/26"
    app_subnet2_name         = "app-subnet2"
    app_subnet2_cidr         = "10.1.0.64/26"
    east_west_firewall_name  = "ingress-user-vm-subnet1"
    db_subnet1_name          = "db-subnet1"
    db_subnet1_cidr          = "10.2.0.0/26"
    batch_subnet_name        = "batch-subnet"
    batch_subnet_cidr        = "10.3.0.0/16"
    ubuntu_patch_day_of_week = "WEDNESDAY"
    ubuntu_patch_hour        = 7
    ubuntu_patch_minute      = 15
    windows_patch_month_day  = 15
    windows_patch_hour       = 22
    windows_patch_minute     = 15
  }

  application_development_defaults = {
    ds_image_family           = "pamdata-ds-gi"
    app_dev_instance_name     = "app-dev-server1"
    app_dev_machine_type      = "e2-standard-4"
    app_dev_boot_disk_size_gb = 360
    app_dev_boot_disk_type    = "pd-standard"
    docker_repo_id            = "pamdata-docker-repo"
    docker_repo_description   = "Repository for container images to run on pamdata infrastructure"
  }

  windows_defaults = {
    windows_workstation_image_family = "pam-windows-workstation"
    windows_template_image_family    = "pam-ww-templates"
    windows_machine_type             = "e2-standard-8"
    windows_gpu_machine_type         = "n1-highmem-16"
  }

  sql_defaults = {
    allowed_consumer_projects = [local.cfg.project_id, "nmfs-vpc-host"]
    psc_endpoint_ip_name      = "psc-to-cloudsql-ip"
    psc_forwarding_rule_name  = "psc-to-cloudsql-endpoint"
  }

  image_pipeline_defaults = {
    cloudbuild_pubsub_topic_name                = "run-monthly-rebuilds"
    cloudbuild_trigger_name                     = "golden-image-build-scheduled"
    packer_builder_service_account_id           = "packer-builder-sa"
    packer_builder_service_account_display_name = "Service Account for building packer images"
    packer_user_password_secret_id              = "packer_user_password"
  }

  iam_defaults = {
    additional_source_readers               = ["user:joshua.leigh@noaa.gov"]
    windows_workstation_sa_account_id       = "windows-workstation-sa"
    windows_workstation_sa_display_name     = "Service account for windows workstation users"
    app_dev_sa_account_id                   = "app-dev-sa"
    app_dev_sa_display_name                 = "Service account for application developers principle group"
    nefsc_minke_detector_sa_account_id      = "nefsc-minke-detector"
    nefsc_minke_detector_sa_display_name    = "Service account for the nefsc minke detector"
    nefsc_humpback_detector_sa_account_id   = "nefsc-humpback-detector"
    nefsc_humpback_detector_sa_display_name = "Service account for the nefsc humpback detector"
    afsc_instinct_sa_account_id             = "afsc-instinct"
    afsc_instinct_sa_display_name           = "Service account for afsc instinct"
    enable_transfer_appliance_bindings      = false
    transfer_appliance_target_bucket        = "nefsc-1"
    transfer_appliance_member_1             = "serviceAccount:ta-c0-e326-9133@transfer-appliance-zimbru.iam.gserviceaccount.com"
    transfer_appliance_member_2             = "serviceAccount:project-804870724004@storage-transfer-service.iam.gserviceaccount.com"
  }

  storage_defaults = {
    snapshot_policy_name      = "dwoodrich-gpu-snap-policy"
    snapshot_target_disk_name = "dwoodrich-gpu3"
  }
}
