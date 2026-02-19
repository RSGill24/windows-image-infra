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
  source            = "./modules/network"
  project_id        = var.project_id
  region            = var.region
  network_name      = local.network_name
  app_subnet1_cidr  = "10.1.0.0/26"
  app_subnet2_cidr  = "10.1.0.64/26"
  db_subnet1_cidr   = "10.2.0.0/26"
  batch_subnet_cidr = "10.3.0.0/16"
  iap_source_range  = "35.235.240.0/20"
  cloud_router_asn  = 64514
  config = {
    network_name      = local.network_name
    app_subnet1_cidr  = "10.1.0.0/26"
    app_subnet2_cidr  = "10.1.0.64/26"
    db_subnet1_cidr   = "10.2.0.0/26"
    batch_subnet_cidr = "10.3.0.0/16"
    iap_source_range  = "35.235.240.0/20"
    cloud_router_asn  = 64514

    dns_service_name  = "dns.googleapis.com"
    dns_policy_name   = "dns-logging"
    iap_ssh_ports     = ["22"]
    iap_rdp_ports     = ["3389"]
    iap_winrm_ports   = ["5986"]
    user_vm_protocols = "all"
  }
}

module "iam" {
  source         = "./modules/iam"
  project_id     = var.project_id
  application_id = var.application_id
  pamdata_admin = [
    "user:daniel.woodrich@noaa.gov",
    "user:jeffrey.walker@noaa.gov",
  ]
  pamdata_supervisors = [
    "user:sofie.vanparijs@noaa.gov",
    "user:rebecca.vanhoeck@noaa.gov",
  ]
  app_developers            = ["user:daniel.woodrich@noaa.gov"]
  transfer_appliance_admins = ["user:rebecca.vanhoeck@noaa.gov"]
  transfer_appliance_users = [
    "user:thomas.sejkora@noaa.gov",
    "user:daniel.woodrich@noaa.gov",
  ]
  nefsc_minke_detector_users = [
    "user:daniel.woodrich@noaa.gov",
    "user:lindsey.transue@noaa.gov",
    local.pamarc_dev_composer_sa,
  ]
  nefsc_humpback_detector_users = [
    "user:daniel.woodrich@noaa.gov",
    "user:lindsey.transue@noaa.gov",
    local.pamarc_dev_composer_sa,
  ]
  afsc_instinct_users = [
    "user:daniel.woodrich@noaa.gov",
    local.pamarc_dev_composer_sa,
    local.afsc_instinct_sa,
  ]
  bucket_users = local.computed_bucket_users
  transfer_appliance_service_accounts = [
    "serviceAccount:ta-c0-e326-9133@transfer-appliance-zimbru.iam.gserviceaccount.com",
    "serviceAccount:project-804870724004@storage-transfer-service.iam.gserviceaccount.com",
  ]
  transfer_appliance_target_bucket = "nefsc-1"
  config = {
    pamdata_admin = [
      "user:daniel.woodrich@noaa.gov",
      "user:jeffrey.walker@noaa.gov",
    ]
    pamdata_supervisors = [
      "user:sofie.vanparijs@noaa.gov",
      "user:rebecca.vanhoeck@noaa.gov",
    ]
    app_developers            = ["user:daniel.woodrich@noaa.gov"]
    transfer_appliance_admins = ["user:rebecca.vanhoeck@noaa.gov"]
    transfer_appliance_users = [
      "user:thomas.sejkora@noaa.gov",
      "user:daniel.woodrich@noaa.gov",
    ]
    nefsc_minke_detector_users = [
      "user:daniel.woodrich@noaa.gov",
      "user:lindsey.transue@noaa.gov",
      local.pamarc_dev_composer_sa,
    ]
    nefsc_humpback_detector_users = [
      "user:daniel.woodrich@noaa.gov",
      "user:lindsey.transue@noaa.gov",
      local.pamarc_dev_composer_sa,
    ]
    afsc_instinct_users = [
      "user:daniel.woodrich@noaa.gov",
      local.pamarc_dev_composer_sa,
      local.afsc_instinct_sa,
    ]
    bucket_users = local.computed_bucket_users
    transfer_appliance_service_accounts = [
      "serviceAccount:ta-c0-e326-9133@transfer-appliance-zimbru.iam.gserviceaccount.com",
      "serviceAccount:project-804870724004@storage-transfer-service.iam.gserviceaccount.com",
    ]
    transfer_appliance_target_bucket = "nefsc-1"

    tau_kms_user_permissions = [
      "iam.serviceAccounts.getIamPolicy",
      "resourcemanager.projects.getIamPolicy",
      "storage.buckets.getIamPolicy",
      "transferappliance.appliances.list",
      "transferappliance.orders.list",
      "transferappliance.orders.update",
      "transferappliance.appliances.get",
      "transferappliance.appliances.update",
      "transferappliance.credentials.get",
    ]
    compute_user_permissions = [
      "compute.instances.start",
      "compute.instances.stop",
      "compute.instances.reset",
      "compute.instances.use",
      "compute.instances.osLogin",
    ]
    bucket_lister_permissions = ["storage.buckets.list"]
    image_builder_permissions = [
      "compute.disks.create", "compute.disks.delete", "compute.disks.useReadOnly",
      "compute.globalOperations.get", "compute.images.get", "compute.images.create",
      "compute.images.list", "compute.images.getFromFamily", "compute.images.deprecate",
      "compute.images.delete", "compute.images.useReadOnly",
      "compute.instances.create", "compute.instances.delete", "compute.instances.get",
      "compute.instances.setMetadata", "compute.instances.setServiceAccount",
      "compute.instances.stop", "compute.machineTypes.get", "compute.subnetworks.use",
      "compute.zoneOperations.get", "compute.zones.get", "compute.projects.get",
    ]
  }
}

module "storage" {
  source     = "./modules/storage"
  project_id = var.project_id
  data_buckets_map = {
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
  bucket_users = local.computed_bucket_users
  depends_on   = [module.iam]
  config = {
    bucket_location = "US"
    # Re-declare map if needed by config, or just pass variables.
    # The original locals had map inside config as well, but module might use var.data_buckets_map 
    # Checking mian.tf again, it passes data_buckets_map as argument AND config. 
    # I will replicate simple config values here.
    bucket_location = "US"
  }
}

module "bigquery" {
  source                = "./modules/bigquery"
  project_id            = var.project_id
  compliance_dataset_id = "pam_wv_instance_controls"
  compliance_table_id   = "pam-wv-instance-controls-table"
  gcs_logs_dataset_id   = "gcs_read_logs"
  config = {
    compliance_dataset_id   = "pam_wv_instance_controls"
    compliance_table_id     = "pam-wv-instance-controls-table"
    gcs_logs_dataset_id     = "gcs_read_logs"
    compliance_description  = "BigQuery dataset for compliance data with dynamic quarterly artifact queries"
    compliance_table_schema = <<EOF
[
  {"name":"ConfigurationName","type":"STRING"},
  {"name":"DependsOn","type":"STRING"},
  {"name":"ModuleName","type":"STRING"},
  {"name":"ModuleVersion","type":"STRING"},
  {"name":"PsDscRunAsCredential","type":"STRING"},
  {"name":"ResourceId","type":"STRING"},
  {"name":"SourceInfo","type":"STRING"},
  {"name":"DurationInSeconds","type":"FLOAT64"},
  {"name":"Error","type":"STRING"},
  {"name":"FinalState","type":"STRING"},
  {"name":"InDesiredState","type":"BOOL"},
  {"name":"InitialState","type":"STRING"},
  {"name":"InstanceName","type":"STRING"},
  {"name":"RebootRequested","type":"BOOL"},
  {"name":"ResourceName","type":"STRING"},
  {"name":"StartDate","type":"STRING"},
  {"name":"StateChanged","type":"BOOL"},
  {"name":"PSComputerName","type":"STRING"},
  {"name":"CimClass","type":"STRING"},
  {"name":"CimInstanceProperties","type":"STRING"},
  {"name":"CimSystemProperties","type":"STRING"},
  {"name":"Compliance","type":"BOOL"},
  {"name":"GCPInstanceName","type":"STRING"},
  {"name":"GCPInstanceId","type":"INT64"},
  {"name":"GCPImageName","type":"STRING"},
  {"name":"GCPAuditUuid","type":"STRING"}
]
EOF
    gcs_log_sink_filter     = <<-EOT
    logName="projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Fdata_access"
    resource.type = "gcs_bucket"
    protoPayload.serviceName="storage.googleapis.com"
    protoPayload.methodName=("storage.objects.get|storage.objects.getRange|storage.objects.compose|storage.objects.rewrite|storage.objects.copy")
  EOT
  }
}

module "image_pipeline" {
  source                 = "./modules/image_pipeline"
  project_id             = var.project_id
  region                 = var.region
  zone                   = var.zone
  rebuild_schedule_cron  = "0 0 16 * *"
  source_repo_name       = "tf-repo-pamdata"
  cloudbuild_config_file = "packer/cloudbuild.yml"
  packer_secret_id       = "packer_user_password"
  pamdata_admin = [
    "user:daniel.woodrich@noaa.gov",
    "user:jeffrey.walker@noaa.gov",
  ]
  snapshot_policy_name               = "dwoodrich-gpu-snap-policy"
  snapshot_days_in_cycle             = 1
  snapshot_start_time                = "04:00"
  snapshot_max_retention_days        = 14
  gpu_disk_name                      = "dwoodrich-gpu3"
  ubuntu_patch_hour                  = 7
  ubuntu_patch_minute                = 15
  ubuntu_patch_day                   = "WEDNESDAY"
  ubuntu_patch_duration              = "1800s"
  windows_patch_hour                 = 22
  windows_patch_minute               = 15
  windows_patch_month_day            = 15
  windows_patch_duration             = "5400s"
  dormant_patch_boot_schedule        = "0 7 * * 3"
  patch_boot_shutdown_start_schedule = "0 22 15 * *"
  patch_boot_shutdown_stop_schedule  = "59 23 15 * *"
  config = {
    rebuild_schedule_cron       = "0 0 16 * *"
    source_repo_name            = "tf-repo-pamdata"
    cloudbuild_config_file      = "packer/cloudbuild.yml"
    packer_secret_id            = "packer_user_password"
    snapshot_policy_name        = "dwoodrich-gpu-snap-policy"
    snapshot_days_in_cycle      = 1
    snapshot_start_time         = "04:00"
    snapshot_max_retention_days = 14
    gpu_disk_name               = "dwoodrich-gpu3"

    ubuntu_patch_hour     = 7
    ubuntu_patch_minute   = 15
    ubuntu_patch_day      = "WEDNESDAY"
    ubuntu_patch_duration = "1800s"

    windows_patch_hour      = 22
    windows_patch_minute    = 15
    windows_patch_month_day = 15
    windows_patch_duration  = "5400s"

    dormant_patch_boot_schedule        = "0 7 * * 3"
    patch_boot_shutdown_start_schedule = "0 22 15 * *"
    patch_boot_shutdown_stop_schedule  = "59 23 15 * *"

    scheduler_data = "Run monthly build"
    image_builder_permissions = [
      "compute.disks.create", "compute.disks.delete", "compute.disks.useReadOnly",
      "compute.globalOperations.get", "compute.images.get", "compute.images.create",
      "compute.images.list", "compute.images.getFromFamily", "compute.images.deprecate",
      "compute.images.delete", "compute.images.useReadOnly",
      "compute.instances.create", "compute.instances.delete", "compute.instances.get",
      "compute.instances.setMetadata", "compute.instances.setServiceAccount",
      "compute.instances.stop", "compute.machineTypes.get", "compute.subnetworks.use",
      "compute.zoneOperations.get", "compute.zones.get", "compute.projects.get",
    ]
  }
}

module "windows_workstation" {
  source                   = "./modules/windows_workstation"
  project_id               = var.project_id
  region                   = var.region
  zone                     = var.zone
  common_labels            = local.common_labels
  ww_image_family          = "pam-windows-workstation"
  ww_template_image_family = "pam-ww-templates"
  ww_machine_type          = "e2-standard-8"
  ww_disk_size_gb          = 250
  ww_disk_type             = "pd-standard"
  gpu_machine_type         = "n1-highmem-16"
  gpu_disk_name            = "dwoodrich-gpu3"
  gpu_accelerator_type     = "nvidia-tesla-t4"
  eric_braen_disk_name     = "ins-copy-eb"
  eric_braen_users         = ["user:eric.braen@noaa.gov"]
  pam_ww_users             = []
  app_subnet2_self_link    = module.network.app_subnet2_self_link
  ww_sa_email              = module.iam.windows_workstation_sa_email
  ww_sa_id                 = module.iam.windows_workstation_sa_id
  compute_user_role_id     = module.iam.compute_user_role_id
  depends_on               = [module.network, module.iam]
  config = {
    ww_image_family          = "pam-windows-workstation"
    ww_template_image_family = "pam-ww-templates"
    ww_machine_type          = "e2-standard-8"
    ww_disk_size_gb          = 250
    ww_disk_type             = "pd-standard"
    gpu_machine_type         = "n1-highmem-16"
    gpu_disk_name            = "dwoodrich-gpu3"
    gpu_accelerator_type     = "nvidia-tesla-t4"
    eric_braen_disk_name     = "ins-copy-eb"
    eric_braen_users         = ["user:eric.braen@noaa.gov"]
    pam_ww_users             = []

    patch_policy_url = local.patch_boot_shutdown_policy_url
    labels = {
      product_name = "pam-ww"
    }
    template_labels = {
      windows_force_reboot_patch_15th = "true"
    }
    gpu_labels = {
      product_name                    = "pam-ww-gpu"
      windows_force_reboot_patch_15th = "true"
    }
  }
}

module "application_development" {
  source                = "./modules/application_development"
  project_id            = var.project_id
  region                = var.region
  zone                  = var.zone
  common_labels         = local.common_labels
  ds_image_family       = "pamdata-ds-gi"
  app_dev_machine_type  = "e2-standard-4"
  app_dev_disk_size_gb  = 360
  app_dev_disk_type     = "pd-standard"
  docker_repo_id        = local.docker_repo_id
  app_subnet1_self_link = module.network.app_subnet1_self_link
  app_dev_sa_email      = module.iam.app_dev_sa_email
  depends_on            = [module.network, module.iam]
  config = {
    ds_image_family      = "pamdata-ds-gi"
    app_dev_machine_type = "e2-standard-4"
    app_dev_disk_size_gb = 360
    app_dev_disk_type    = "pd-standard"
    docker_repo_id       = local.docker_repo_id
    resource_policies = [
      local.dormant_patch_boot_policy_url
    ]
    labels = {
      ubuntu_force_reboot_patch_weds_7utc = true
    }
  }
}
