# Project admin least-privilege set (no Owner/Editor bindings).
locals {
  admin_roles = toset([
    "roles/storage.admin",
    "roles/compute.admin",
    "roles/iap.admin",
    "roles/osconfig.admin",
    "roles/secretmanager.admin",
    "roles/source.admin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/iam.roleAdmin",
    "roles/securitycenter.admin",
    "roles/logging.admin",
    "roles/dns.admin",
    "roles/bigquery.admin",
    "roles/run.admin",
    "roles/cloudscheduler.admin",
    "roles/cloudbuild.builds.editor",
    "roles/pubsub.admin",
    "roles/containeranalysis.admin",
    "roles/artifactregistry.admin",
    "roles/cloudsql.admin",
    "roles/servicedirectory.admin",
    "roles/batch.admin",
  ])

  admin_role_bindings = {
    for pair in setproduct(var.pamdata_admin, local.admin_roles) :
    "${pair[0]}|${pair[1]}" => {
      member = pair[0]
      role   = pair[1]
    }
  }

  all_noaa_objectviewer_buckets = toset(concat(
    var.standard_bucket_names,
    var.additional_bucket_objectviewer_buckets,
  ))

  all_noaa_objectviewer_bindings = {
    for pair in setproduct(local.all_noaa_objectviewer_buckets, toset(var.bucket_users)) :
    "${pair[0]}|${pair[1]}" => {
      bucket = pair[0]
      member = pair[1]
    }
  }

  app_dev_sa_member                 = "serviceAccount:${google_service_account.app_dev_sa.account_id}@${var.project_id}.iam.gserviceaccount.com"
  windows_workstation_sa_member     = "serviceAccount:${google_service_account.windows_workstation_sa.account_id}@${var.project_id}.iam.gserviceaccount.com"
  nefsc_minke_detector_sa_member    = "serviceAccount:${google_service_account.nefsc_minke_detector.account_id}@${var.project_id}.iam.gserviceaccount.com"
  nefsc_humpback_detector_sa_member = "serviceAccount:${google_service_account.nefsc_humpback_detector.account_id}@${var.project_id}.iam.gserviceaccount.com"
  afsc_instinct_sa_member           = "serviceAccount:${google_service_account.afsc_instinct.account_id}@${var.project_id}.iam.gserviceaccount.com"

  pam_ww_tmp_members = toset(concat(var.pam_ww_users1, [
    local.windows_workstation_sa_member,
    local.nefsc_minke_detector_sa_member,
    local.nefsc_humpback_detector_sa_member,
    var.composer_service_account_member,
    local.afsc_instinct_sa_member,
  ]))
}

resource "google_project_iam_member" "project_admin_roles" {
  for_each = local.admin_role_bindings

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}

# Composer and detector pipeline roles
resource "google_project_iam_member" "cloud_composer_run_developer" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = var.composer_service_account_member
}

resource "google_project_iam_member" "cloud_composer_batch_developer" {
  project = var.project_id
  role    = "roles/batch.jobsEditor"
  for_each = toset([
    local.afsc_instinct_sa_member,
    var.composer_service_account_member,
  ])
  member = each.key
}

resource "google_project_iam_member" "cloud_composer_batch_reporter" {
  project = var.project_id
  role    = "roles/batch.agentReporter"
  member  = local.afsc_instinct_sa_member
}

resource "google_project_iam_member" "cloud_composer_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = var.composer_service_account_member
}

resource "google_project_iam_member" "cloud_composer_pamdata_intermediates_user" {
  project  = var.project_id
  role     = "roles/storage.objectAdmin"
  for_each = toset(concat(var.nefsc_minke_detector_users, var.nefsc_humpback_detector_users, var.afsc_instinct_users))
  member   = each.key

  condition {
    title       = "composer"
    description = "restrict admin to prefix composer/"
    expression  = "resource.name.startsWith('projects/_/buckets/pamdata-app-intermediates/objects/composer/')"
  }
}

resource "google_project_iam_member" "cloud_composer_pab_detector_user" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  for_each = toset([
    local.afsc_instinct_sa_member,
    var.composer_service_account_member,
  ])
  member = each.key

  condition {
    title       = "composer read write to pab"
    description = "composer read write to pab"
    expression  = "resource.name.startsWith('projects/_/buckets/nefsc-1-pab/objects/DETECTORS_AND_SOFTWARE')"
  }
}

resource "google_service_account_iam_member" "app_dev_sa_members" {
  service_account_id = google_service_account.app_dev_sa.id
  role               = "roles/iam.serviceAccountUser"
  for_each           = toset(var.app_developers)
  member             = each.key
}

resource "google_service_account_iam_member" "ww_sa_members" {
  service_account_id = google_service_account.windows_workstation_sa.id
  role               = "roles/iam.serviceAccountUser"
  for_each           = toset(var.pam_ww_users1)
  member             = each.key
}

resource "google_service_account_iam_member" "afsc_instinct_members" {
  service_account_id = google_service_account.afsc_instinct.id
  role               = "roles/iam.serviceAccountUser"
  for_each           = toset(var.afsc_instinct_users)
  member             = each.key
}

resource "google_service_account_iam_member" "nefsc_minke_detector_members" {
  service_account_id = google_service_account.nefsc_minke_detector.id
  role               = "roles/iam.serviceAccountUser"
  for_each           = toset(var.nefsc_minke_detector_users)
  member             = each.key
}

resource "google_service_account_iam_member" "nefsc_humpback_detector_members" {
  service_account_id = google_service_account.nefsc_humpback_detector.id
  role               = "roles/iam.serviceAccountUser"
  for_each           = toset(var.nefsc_humpback_detector_users)
  member             = each.key
}

resource "google_project_iam_member" "app_dev_iap_tunnel" {
  project  = var.project_id
  role     = "roles/iap.tunnelResourceAccessor"
  for_each = toset(var.app_developers)
  member   = each.key
}

resource "google_project_iam_member" "app_dev_sa_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  for_each = toset([
    local.app_dev_sa_member,
    local.afsc_instinct_sa_member,
  ])
  member = each.key
}

resource "google_project_iam_member" "app_dev_sa_metrics" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  for_each = toset([
    local.app_dev_sa_member,
    local.afsc_instinct_sa_member,
  ])
  member = each.key
}

resource "google_project_iam_member" "app_dev_sa_artifacts_admin" {
  project = var.project_id
  role    = "roles/artifactregistry.repoAdmin"
  member  = local.app_dev_sa_member
}

resource "google_project_iam_member" "app_dev_sa_storage_obj_admin_intermediates" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = local.app_dev_sa_member

  condition {
    title       = "prefix_appdev"
    description = "restrict admin to prefix appdev/"
    expression  = "resource.name.startsWith('projects/_/buckets/pamdata-app-intermediates/objects/appdev/')"
  }
}

resource "google_project_iam_member" "app_dev_sa_storage_obj_admin_outputs" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = local.app_dev_sa_member

  condition {
    title       = "prefix_appdev"
    description = "restrict admin to prefix appdev/"
    expression  = "resource.name.startsWith('projects/_/buckets/pamdata-app-outputs/objects/appdev/')"
  }
}

resource "google_project_iam_member" "afsc_instinct_user_log_viewer" {
  project  = var.project_id
  role     = "roles/logging.viewer"
  for_each = toset(var.afsc_instinct_users)
  member   = each.key
}

resource "google_project_iam_member" "nefsc_minke_user_log_viewer" {
  project  = var.project_id
  role     = "roles/logging.viewer"
  for_each = toset(var.nefsc_minke_detector_users)
  member   = each.key
}

resource "google_project_iam_member" "nefsc_humpback_out" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = local.nefsc_humpback_detector_sa_member

  condition {
    title       = "approved_output_location"
    description = "restrict detector outputs to the approved output location"
    expression  = "resource.name.startsWith('projects/_/buckets/nefsc-1-detector-output/objects/PYTHON_HUMPBACK_CNN/Raw/')"
  }
}

resource "google_project_iam_member" "nefsc_humpback_out2" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = local.nefsc_humpback_detector_sa_member

  condition {
    title       = "approved_output_location"
    description = "restrict detector outputs to the approved output location"
    expression  = "resource.name.startsWith('projects/_/buckets/nefsc-1-pab/objects/DETECTOR_OUTPUT/PYTHON_HUMPBACK_CNN/Raw/')"
  }
}

resource "google_project_iam_member" "nefsc_humpback_user_log_viewer" {
  project  = var.project_id
  role     = "roles/logging.viewer"
  for_each = toset(var.nefsc_humpback_detector_users)
  member   = each.key
}

resource "google_project_iam_member" "detectors_out_appdev" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  for_each = toset([
    local.nefsc_minke_detector_sa_member,
    local.nefsc_humpback_detector_sa_member,
    local.afsc_instinct_sa_member,
  ])
  member = each.key

  condition {
    title       = "approved_output_location"
    description = "restrict detector outputs to the approved output location"
    expression  = "resource.name.startsWith('projects/_/buckets/pamdata-app-outputs/objects/appdev/')"
  }
}

resource "google_project_iam_member" "nefsc_minke_out" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = local.nefsc_minke_detector_sa_member

  condition {
    title       = "approved_output_location"
    description = "restrict detector outputs to the approved output location"
    expression  = "resource.name.startsWith('projects/_/buckets/nefsc-1-pab/objects/DETECTOR_OUTPUT/PYTHON_MINKE_KETOS_v0.2/Raw/')"
  }
}

resource "google_project_iam_member" "cloud_run_dev" {
  project  = var.project_id
  role     = "roles/run.developer"
  for_each = toset(concat(var.nefsc_minke_detector_users, var.nefsc_humpback_detector_users))
  member   = each.key
}

resource "google_project_iam_member" "cloud_run_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  for_each = toset(concat(
    var.nefsc_minke_detector_users,
    var.nefsc_humpback_detector_users,
    [local.afsc_instinct_sa_member],
  ))
  member = each.key
}

resource "google_project_iam_member" "ww_iap_tunnel_members" {
  project  = var.project_id
  role     = "roles/iap.tunnelResourceAccessor"
  for_each = toset(var.pam_ww_users1)
  member   = each.key
}

resource "google_project_iam_member" "ww_compute_viewers" {
  project  = var.project_id
  role     = "roles/compute.viewer"
  for_each = toset(var.pam_ww_users1)
  member   = each.key
}

resource "google_project_iam_member" "ww_sa1_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = local.windows_workstation_sa_member
}

resource "google_project_iam_member" "ww_sa1_metrics" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = local.windows_workstation_sa_member
}

resource "google_storage_bucket_iam_binding" "data_bucket_data_admin" {
  for_each = var.data_buckets_map
  bucket   = each.key
  role     = "roles/storage.objectUser"
  members  = each.value.data_admins
}

resource "google_storage_bucket_iam_member" "pam_ww_tmp_object_admin" {
  bucket   = "pam-ww-tmp"
  role     = "roles/storage.objectUser"
  for_each = local.pam_ww_tmp_members
  member   = each.key
}

resource "google_storage_bucket_iam_member" "nefsc_1_detector_output_object_admin" {
  bucket   = "nefsc-1-detector-output"
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["nefsc-1"].data_admins, var.data_buckets_map["nefsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "nefsc_1_ancillary_data_object_admin" {
  bucket   = "nefsc-1-ancillary-data"
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["nefsc-1"].data_admins, var.data_buckets_map["nefsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "nefsc_1_pab_data_object_admin" {
  bucket   = "nefsc-1-pab"
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["nefsc-1"].data_admins, var.data_buckets_map["nefsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "pifsc_1_detector_output_object_admin" {
  bucket   = "pifsc-1-detector-output"
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["pifsc-1"].data_admins, var.data_buckets_map["pifsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "pifsc_1_working_object_admin" {
  bucket   = "pifsc-1-working"
  role     = "roles/storage.objectUser"
  for_each = try(toset(var.data_buckets_map["pifsc-1"].data_admins), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "swfsc_1_working_data_object_admin" {
  bucket   = "swfsc-1-working"
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["swfsc-1"].data_admins, var.data_buckets_map["swfsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "afsc_1_working_object_admin" {
  bucket   = "afsc-1-working"
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["afsc-1"].data_admins, var.data_buckets_map["afsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "afsc_1_temp_object_admin" {
  bucket   = "afsc-1-temp"
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["afsc-1"].data_admins, var.data_buckets_map["afsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "sefsc_1_working_object_admin" {
  bucket   = "sefsc-1-working"
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["sefsc-1"].data_admins, var.data_buckets_map["sefsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "sefsc_2_working_object_admin" {
  bucket   = "sefsc-2-working"
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["sefsc-2"].data_admins, var.data_buckets_map["sefsc-2"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "ost_1_working_object_admin" {
  bucket   = "ost-1-working"
  role     = "roles/storage.objectUser"
  for_each = toset([
    "user:samara.h.haven@noaa.gov",
    "user:murali.moore@noaa.gov",
    "user:louisa.li@noaa.gov",
  ])
  member = each.key
}

resource "google_project_iam_member" "project_source_readers" {
  project  = var.project_id
  role     = "roles/source.reader"
  for_each = toset(concat(var.pamdata_supervisors, var.additional_source_readers))
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_source_repo_readers" {
  project  = var.project_id
  role     = "roles/source.reader"
  for_each = toset(var.additional_source_repo_readers)
  member   = each.key
}

resource "google_project_iam_member" "supervisor_network_viewer" {
  project  = var.project_id
  role     = "roles/compute.networkViewer"
  for_each = toset(var.pamdata_supervisors)
  member   = each.key
}

resource "google_project_iam_member" "supervisor_compute_viewer" {
  project  = var.project_id
  role     = "roles/compute.viewer"
  for_each = toset(var.pamdata_supervisors)
  member   = each.key
}

resource "google_project_iam_member" "supervisor_artifact_reader" {
  project  = var.project_id
  role     = "roles/artifactregistry.reader"
  for_each = toset(var.pamdata_supervisors)
  member   = each.key
}

resource "google_project_iam_member" "all_noaa_bucket_viewer" {
  project  = var.project_id
  role     = google_project_iam_custom_role.bucket_lister.id
  for_each = toset(var.bucket_users)
  member   = each.key
}

resource "google_project_iam_member" "all_noaa_bucket_metadata_viewer" {
  project  = var.project_id
  role     = "roles/storage.insightsCollectorService"
  for_each = toset(var.bucket_users)
  member   = each.key
}

resource "google_storage_bucket_iam_member" "all_noaa_bucket_objects_viewer" {
  for_each = local.all_noaa_objectviewer_bindings

  bucket = each.value.bucket
  role   = "roles/storage.objectViewer"
  member = each.value.member
}

resource "google_storage_bucket_iam_member" "all_noaa_bucket_objects_viewer_nefsc_1_special" {
  bucket = "nefsc-1"
  role   = "roles/storage.objectViewer"
  member = var.aa_ncsi_service_account_member
}

resource "google_project_iam_member" "tau_kms_admin" {
  project  = var.project_id
  role     = "roles/cloudkms.admin"
  for_each = toset(var.pamdata_transfer_appliance_admins)
  member   = each.key
}

resource "google_project_iam_member" "tau_service_account_admin" {
  project  = var.project_id
  role     = "roles/iam.serviceAccountAdmin"
  for_each = toset(var.pamdata_transfer_appliance_admins)
  member   = each.key
}

resource "google_project_iam_member" "tau_transfer_appliance_admin" {
  project  = var.project_id
  role     = "roles/transferappliance.admin"
  for_each = toset(var.pamdata_transfer_appliance_admins)
  member   = each.key
}

resource "google_project_iam_member" "tau_kms_user" {
  project  = var.project_id
  role     = google_project_iam_custom_role.tau_kms_user_role.id
  for_each = toset(var.pamdata_transfer_appliance_users)
  member   = each.key
}

resource "google_project_iam_member" "tau_kms_user_predefined" {
  project  = var.project_id
  role     = "roles/transferappliance.viewer"
  for_each = toset(var.pamdata_transfer_appliance_users)
  member   = each.key
}

data "google_secret_manager_secret" "test_secret_pgpmadb" {
  count     = var.enable_pg_secret_bindings ? 1 : 0
  secret_id = "test-secret-pgpmadb"
}

resource "google_secret_manager_secret_iam_member" "pgsec_viewer" {
  for_each = var.enable_pg_secret_bindings ? toset([
    local.afsc_instinct_sa_member,
    local.app_dev_sa_member,
  ]) : toset([])

  project   = data.google_secret_manager_secret.test_secret_pgpmadb[0].project
  secret_id = data.google_secret_manager_secret.test_secret_pgpmadb[0].secret_id
  role      = "roles/secretmanager.viewer"
  member    = each.key
}

resource "google_secret_manager_secret_iam_member" "pgsec_accessor" {
  for_each = var.enable_pg_secret_bindings ? toset([
    local.afsc_instinct_sa_member,
    local.app_dev_sa_member,
  ]) : toset([])

  project   = data.google_secret_manager_secret.test_secret_pgpmadb[0].project
  secret_id = data.google_secret_manager_secret.test_secret_pgpmadb[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.key
}

data "google_secret_manager_secret" "taiki_api_key" {
  count     = var.enable_taiki_secret_bindings ? 1 : 0
  secret_id = "taiki-api-key"
}

resource "google_secret_manager_secret_iam_member" "taiki_manager" {
  count = var.enable_taiki_secret_bindings ? 1 : 0

  project   = data.google_secret_manager_secret.taiki_api_key[0].project
  secret_id = data.google_secret_manager_secret.taiki_api_key[0].secret_id
  role      = "roles/secretmanager.secretVersionManager"
  member    = "user:taiki.sakai@noaa.gov"
}

resource "google_secret_manager_secret_iam_member" "taiki_viewer" {
  for_each = var.enable_taiki_secret_bindings ? toset([
    "user:taiki.sakai@noaa.gov",
    local.windows_workstation_sa_member,
  ]) : toset([])

  project   = data.google_secret_manager_secret.taiki_api_key[0].project
  secret_id = data.google_secret_manager_secret.taiki_api_key[0].secret_id
  role      = "roles/secretmanager.viewer"
  member    = each.key
}

resource "google_secret_manager_secret_iam_member" "taiki_accessor" {
  for_each = var.enable_taiki_secret_bindings ? toset([
    "user:taiki.sakai@noaa.gov",
    local.windows_workstation_sa_member,
  ]) : toset([])

  project   = data.google_secret_manager_secret.taiki_api_key[0].project
  secret_id = data.google_secret_manager_secret.taiki_api_key[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.key
}

resource "google_bigquery_dataset_iam_member" "ww_packer_write_to_bq_sink" {
  dataset_id = var.compliance_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = local.windows_workstation_sa_member
}

resource "google_project_iam_member" "ww_packer_write_to_bq_sink_job_create" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = local.windows_workstation_sa_member
}
