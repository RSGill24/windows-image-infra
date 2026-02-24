locals {
  app_dev_sa_member                 = "serviceAccount:${google_service_account.app_dev_sa.account_id}@${var.project_id}.iam.gserviceaccount.com"
  windows_workstation_sa_member     = "serviceAccount:${google_service_account.windows_workstation_sa.account_id}@${var.project_id}.iam.gserviceaccount.com"
  nefsc_minke_detector_sa_member    = "serviceAccount:${google_service_account.nefsc_minke_detector.account_id}@${var.project_id}.iam.gserviceaccount.com"
  nefsc_humpback_detector_sa_member = "serviceAccount:${google_service_account.nefsc_humpback_detector.account_id}@${var.project_id}.iam.gserviceaccount.com"
  afsc_instinct_sa_member           = "serviceAccount:${google_service_account.afsc_instinct.account_id}@${var.project_id}.iam.gserviceaccount.com"
  composer_sa_member                = var.composer_service_account_member != "" ? var.composer_service_account_member : "serviceAccount:composer-sa@ggn-nmfs-pamarc-dev-1.iam.gserviceaccount.com"

  pam_ww_tmp_members = toset(concat(local.pam_ww_users, [
    local.windows_workstation_sa_member,
    local.nefsc_minke_detector_sa_member,
    local.nefsc_humpback_detector_sa_member,
    local.composer_sa_member,
    local.afsc_instinct_sa_member,
  ]))

  pam_ww_instance_names = {
    for member in local.pam_ww_users :
    member => "${lower(replace(replace(replace(member, "/[^a-z0-9]+/", "-"), "user-", ""), "noaa-gov-", ""))}-pam-ww"
  }
}

################################################################################
# SECTION 1: PROJECT ADMINISTRATORS
# High-level permissions for the pamdata_admin group
################################################################################

resource "google_project_iam_member" "proj_admin_storage_admin" {
  project  = var.project_id
  role     = "roles/storage.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_compute_admin" {
  project  = var.project_id
  role     = "roles/compute.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_iap_admin" {
  project  = var.project_id
  role     = "roles/iap.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_osconfig" {
  project  = var.project_id
  role     = "roles/osconfig.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_secret_admin" {
  project  = var.project_id
  role     = "roles/secretmanager.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_source_repo_admin" {
  project  = var.project_id
  role     = "roles/source.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_source_service_admin" {
  project  = var.project_id
  role     = "roles/serviceusage.serviceUsageAdmin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_role_admin" {
  project  = var.project_id
  role     = "roles/iam.roleAdmin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_sec" {
  project  = var.project_id
  role     = "roles/securitycenter.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_logging" {
  project  = var.project_id
  role     = "roles/logging.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

# Needed for turning on DNS logging
resource "google_project_iam_member" "proj_admin_dns" {
  project  = var.project_id
  role     = "roles/dns.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_bq" {
  project  = var.project_id
  role     = "roles/bigquery.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_run" {
  project  = var.project_id
  role     = "roles/run.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_cloud_scheduler" {
  project  = var.project_id
  role     = "roles/cloudscheduler.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_cloudbuild" {
  project  = var.project_id
  role     = "roles/cloudbuild.builds.editor"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_pubsub" {
  project  = var.project_id
  role     = "roles/pubsub.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_container_analysis" {
  project  = var.project_id
  role     = "roles/containeranalysis.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_container_registry_update" {
  project  = var.project_id
  role     = "roles/artifactregistry.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_sql" {
  project  = var.project_id
  role     = "roles/cloudsql.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_sql_cxns" {
  project  = var.project_id
  role     = "roles/servicedirectory.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

resource "google_project_iam_member" "proj_admin_batch" {
  project  = var.project_id
  role     = "roles/batch.admin"
  for_each = toset(var.pamdata_admin)
  member   = each.key
}

################################################################################
# SECTION 2: DEFAULT COMPUTE & SYSTEM ACCOUNTS
################################################################################

data "google_project" "default" {
  project_id = var.project_id
}

data "google_compute_default_service_account" "default" {
  project = var.project_id
}

# Bind project owner to project compute engine account
resource "google_service_account_iam_member" "proj_admin_default_compute_user" {
  service_account_id = data.google_compute_default_service_account.default.id
  role               = "roles/iam.serviceAccountUser"
  for_each           = toset(var.pamdata_admin)
  member             = each.key
}

# Needed to allow terraform to manage compute instances correctly
resource "google_project_iam_member" "default_compute_account_instance_admin" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${data.google_project.default.number}@compute-system.iam.gserviceaccount.com"
}

################################################################################
# SECTION 3: APP DEVELOPERS
# Permissions for app_developers users and the app-dev-sa
################################################################################

# --- App Developer Users ---

resource "google_compute_instance_iam_member" "app_dev_osadminlogin_users" {
  project       = var.project_id
  zone          = var.zone1
  instance_name = "app-dev-server1"
  role          = "roles/compute.osAdminLogin"
  for_each      = toset(var.app_developers)
  member        = each.key
}

resource "google_compute_instance_iam_member" "app_dev_compute_user" {
  project       = var.project_id
  zone          = var.zone1
  instance_name = "app-dev-server1"
  role          = google_project_iam_custom_role.compute_user.id
  for_each      = toset(var.app_developers)
  member        = each.key
}

resource "google_project_iam_member" "app_dev_iap_tunnel" {
  project  = var.project_id
  role     = "roles/iap.tunnelResourceAccessor"
  for_each = toset(var.app_developers)
  member   = each.key
}

resource "google_service_account_iam_member" "app_dev_sa_members" {
  service_account_id = google_service_account.app_dev_sa.id
  role               = "roles/iam.serviceAccountUser"
  for_each           = toset(var.app_developers)
  member             = each.key
}

# --- App Dev Service Account & Secrets ---

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
    description = "restrict admin to prefix 'appdev/'"
    expression  = "resource.name.startsWith('projects/_/buckets/${var.named_bucket_names.app_intermediates}/objects/appdev/')"
  }
}

resource "google_project_iam_member" "app_dev_sa_storage_obj_admin_outputs" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = local.app_dev_sa_member

  condition {
    title       = "prefix_appdev"
    description = "restrict admin to prefix 'appdev/'"
    expression  = "resource.name.startsWith('projects/_/buckets/${var.named_bucket_names.app_outputs}/objects/appdev/')"
  }
}

################################################################################
# SECTION 4: WINDOWS WORKSTATIONS (PAM-WW)
################################################################################

resource "google_storage_bucket_iam_member" "pam_ww_tmp_object_admin" {
  bucket   = var.named_bucket_names.pam_ww_tmp
  role     = "roles/storage.objectUser"
  for_each = local.pam_ww_tmp_members
  member   = each.key
}

resource "google_service_account_iam_member" "ww_sa_members" {
  service_account_id = google_service_account.windows_workstation_sa.id
  role               = "roles/iam.serviceAccountUser"
  for_each           = toset(local.pam_ww_users)
  member             = each.key
}

resource "google_project_iam_member" "ww_iap_tunnel_members" {
  project  = var.project_id
  role     = "roles/iap.tunnelResourceAccessor"
  for_each = toset(local.pam_ww_users)
  member   = each.key
}

resource "google_iap_tunnel_instance_iam_member" "ww_iap_tunnel_instance_members" {
  project  = var.project_id
  zone     = var.zone1
  for_each = toset(local.pam_ww_users)

  instance = local.pam_ww_instance_names[each.key]
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.key
}

resource "google_project_iam_member" "ww_compute_viewers" {
  project  = var.project_id
  role     = "roles/compute.viewer"
  for_each = toset(local.pam_ww_users)
  member   = each.key
}

# Instance specific permissions: oslogin bound to instance
resource "google_compute_instance_iam_member" "pam_ww_login" {
  for_each = toset(local.pam_ww_users)

  zone          = var.zone1
  project       = var.project_id
  instance_name = local.pam_ww_instance_names[each.key]
  role          = google_project_iam_custom_role.compute_user.id
  member        = each.value
}

# Allow user to delete their own VM
resource "google_project_iam_member" "self_delete_vm" {
  for_each = toset(local.pam_ww_users)

  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = each.key

  condition {
    title       = "SelfDeleteOk"
    description = "allow user to delete their own VM, important for prompt pam-ww updates"
    expression  = "resource.name == 'projects/${var.project_id}/zones/${var.zone1}/instances/${local.pam_ww_instance_names[each.key]}'"
  }
}

# Compliance Tracking: Allow windows workstations and packer sa to write to bq sink
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

# Taiki Secret Manager Roles
data "google_secret_manager_secret" "taiki_api_key" {
  count     = var.enable_taiki_secret_bindings ? 1 : 0
  secret_id = "taiki-api-key"
}

resource "google_secret_manager_secret_iam_member" "manager" {
  count = var.enable_taiki_secret_bindings ? 1 : 0

  project   = data.google_secret_manager_secret.taiki_api_key[0].project
  secret_id = data.google_secret_manager_secret.taiki_api_key[0].secret_id
  role      = "roles/secretmanager.secretVersionManager"
  member    = "user:taiki.sakai@noaa.gov"
}

resource "google_secret_manager_secret_iam_member" "viewer" {
  for_each = var.enable_taiki_secret_bindings ? toset([
    "user:taiki.sakai@noaa.gov",
    local.windows_workstation_sa_member,
  ]) : toset([])

  project   = data.google_secret_manager_secret.taiki_api_key[0].project
  secret_id = data.google_secret_manager_secret.taiki_api_key[0].secret_id
  role      = "roles/secretmanager.viewer"
  member    = each.key
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = var.enable_taiki_secret_bindings ? toset([
    "user:taiki.sakai@noaa.gov",
    local.windows_workstation_sa_member,
  ]) : toset([])

  project   = data.google_secret_manager_secret.taiki_api_key[0].project
  secret_id = data.google_secret_manager_secret.taiki_api_key[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.key
}

################################################################################
# SECTION 5: SCIENCE & DETECTOR ROLES (AFSC, NEFSC, ETC.)
################################################################################

# --- AFSC Instinct ---

resource "google_service_account_iam_member" "afsc_instinct_members" {
  service_account_id = google_service_account.afsc_instinct.id
  role               = "roles/iam.serviceAccountUser"
  for_each           = toset(var.afsc_instinct_users)
  member             = each.key
}

resource "google_project_iam_member" "afsc_instinct_user_log_viewer" {
  project  = var.project_id
  role     = "roles/logging.viewer"
  for_each = toset(var.afsc_instinct_users)
  member   = each.key
}

# --- NEFSC Minke ---

resource "google_service_account_iam_member" "nefsc_minke_detector_members" {
  service_account_id = google_service_account.nefsc_minke_detector.id
  role               = "roles/iam.serviceAccountUser"
  for_each           = toset(var.nefsc_minke_detector_users)
  member             = each.key
}

resource "google_project_iam_member" "nefsc_minke_user_log_viewer" {
  project  = var.project_id
  role     = "roles/logging.viewer"
  for_each = toset(var.nefsc_minke_detector_users)
  member   = each.key
}

resource "google_project_iam_member" "nefsc_minke_out" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = local.nefsc_minke_detector_sa_member

  condition {
    title       = "approved_output_location"
    description = "restrict detector outputs to the approved output location"
    expression  = "resource.name.startsWith('projects/_/buckets/${var.named_bucket_names.nefsc_1_pab}/objects/DETECTOR_OUTPUT/PYTHON_MINKE_KETOS_v0.2/Raw/')"
  }
}

# --- NEFSC Humpback ---

resource "google_service_account_iam_member" "nefsc_humpback_detector_members" {
  service_account_id = google_service_account.nefsc_humpback_detector.id
  role               = "roles/iam.serviceAccountUser"
  for_each           = toset(var.nefsc_humpback_detector_users)
  member             = each.key
}

resource "google_project_iam_member" "nefsc_humpback_out" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = local.nefsc_humpback_detector_sa_member

  condition {
    title       = "approved_output_location"
    description = "restrict detector outputs to the approved output location"
    expression  = "resource.name.startsWith('projects/_/buckets/${var.named_bucket_names.nefsc_1_detector_output}/objects/PYTHON_HUMPBACK_CNN/Raw/')"
  }
}

resource "google_project_iam_member" "nefsc_humpback_out2" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = local.nefsc_humpback_detector_sa_member

  condition {
    title       = "approved_output_location"
    description = "restrict detector outputs to the approved output location"
    expression  = "resource.name.startsWith('projects/_/buckets/${var.named_bucket_names.nefsc_1_pab}/objects/DETECTOR_OUTPUT/PYTHON_HUMPBACK_CNN/Raw/')"
  }
}

resource "google_project_iam_member" "nefsc_humpback_user_log_viewer" {
  project  = var.project_id
  role     = "roles/logging.viewer"
  for_each = toset(var.nefsc_humpback_detector_users)
  member   = each.key
}

# --- Shared Detector Output Permissions ---

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
    expression  = "resource.name.startsWith('projects/_/buckets/${var.named_bucket_names.app_outputs}/objects/appdev/')"
  }
}

# --- Cloud Run for Science Users ---

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

################################################################################
# SECTION 6: CLOUD COMPOSER (AIRFLOW)
################################################################################

resource "google_project_iam_member" "cloud_composer_run_developer" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = local.composer_sa_member
}

resource "google_project_iam_member" "cloud_composer_batch_developer" {
  project = var.project_id
  role    = "roles/batch.jobsEditor"
  for_each = toset([
    local.afsc_instinct_sa_member,
    local.composer_sa_member,
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
  member  = local.composer_sa_member
}

resource "google_project_iam_member" "cloud_composer_pamdata_intermediates_user" {
  project  = var.project_id
  role     = "roles/storage.objectAdmin"
  for_each = toset(concat(var.nefsc_minke_detector_users, var.nefsc_humpback_detector_users, var.afsc_instinct_users))
  member   = each.key

  condition {
    title       = "composer"
    description = "restrict admin to prefix 'composer/'"
    expression  = "resource.name.startsWith('projects/_/buckets/${var.named_bucket_names.app_intermediates}/objects/composer/')"
  }
}

resource "google_project_iam_member" "cloud_composer_pab_detector_user" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  for_each = toset([
    local.afsc_instinct_sa_member,
    local.composer_sa_member,
  ])
  member = each.key

  condition {
    title       = "composer read write to pab"
    description = "composer read write to pab"
    expression  = "resource.name.startsWith('projects/_/buckets/${var.named_bucket_names.nefsc_1_pab}/objects/DETECTORS_AND_SOFTWARE')"
  }
}

################################################################################
# SECTION 7: TRANSFER APPLIANCE
################################################################################

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

################################################################################
# SECTION 8: SUPERVISORS
################################################################################

resource "google_project_iam_member" "network_viewer" {
  project  = var.project_id
  role     = "roles/compute.networkViewer"
  for_each = toset(var.pamdata_supervisors)
  member   = each.key
}

resource "google_project_iam_member" "compute_viewer" {
  project  = var.project_id
  role     = "roles/compute.viewer"
  for_each = toset(var.pamdata_supervisors)
  member   = each.key
}

resource "google_project_iam_member" "artifact_reg_reader" {
  project  = var.project_id
  role     = "roles/artifactregistry.reader"
  for_each = toset(var.pamdata_supervisors)
  member   = each.key
}

resource "google_project_iam_member" "source_reader" {
  project = var.project_id
  role    = "roles/source.reader"
  for_each = toset(distinct(concat(
    var.pamdata_supervisors,
    ["user:joshua.le@noaa.gov"],
    var.additional_source_readers,
  )))
  member = each.key
}

################################################################################
# SECTION 9: DATA AUTHORITY & BUCKET PERMISSIONS
################################################################################

# --- Data Admins ---

resource "google_storage_bucket_iam_binding" "data_bucket_data_admin" {
  for_each = var.data_buckets_map
  bucket   = each.key
  role     = "roles/storage.objectUser"
  members  = each.value.data_admins
}

# --- Specific Working Buckets Roles (FMC Specific) ---

resource "google_storage_bucket_iam_member" "nefsc_1_detector_output_object_admin" {
  bucket   = var.named_bucket_names.nefsc_1_detector_output
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["nefsc-1"].data_admins, var.data_buckets_map["nefsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "nefsc_1_ancillary_data_object_admin" {
  bucket   = var.named_bucket_names.nefsc_1_ancillary_data
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["nefsc-1"].data_admins, var.data_buckets_map["nefsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "nefsc_1_pab_data_object_admin" {
  bucket   = var.named_bucket_names.nefsc_1_pab
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["nefsc-1"].data_admins, var.data_buckets_map["nefsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "pifsc_1_detector_output_object_admin" {
  bucket   = var.named_bucket_names.pifsc_1_detector_output
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["pifsc-1"].data_admins, var.data_buckets_map["pifsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "pifsc_1_working_object_admin" {
  bucket   = var.named_bucket_names.pifsc_1_working
  role     = "roles/storage.objectUser"
  for_each = try(toset(var.data_buckets_map["pifsc-1"].data_admins), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "swfsc_1_working_data_object_admin" {
  bucket   = var.named_bucket_names.swfsc_1_working
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["swfsc-1"].data_admins, var.data_buckets_map["swfsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "afsc_1_working_object_admin" {
  bucket   = var.named_bucket_names.afsc_1_working
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["afsc-1"].data_admins, var.data_buckets_map["afsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "afsc_1_temp_object_admin" {
  bucket   = var.named_bucket_names.afsc_1_temp
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["afsc-1"].data_admins, var.data_buckets_map["afsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "sefsc_1_working_object_admin" {
  bucket   = var.named_bucket_names.sefsc_1_working
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["sefsc-1"].data_admins, var.data_buckets_map["sefsc-1"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "sefsc_2_working_object_admin" {
  bucket   = var.named_bucket_names.sefsc_2_working
  role     = "roles/storage.objectUser"
  for_each = try(toset(concat(var.data_buckets_map["sefsc-2"].data_admins, var.data_buckets_map["sefsc-2"].all_users)), toset([]))
  member   = each.key
}

resource "google_storage_bucket_iam_member" "ost_1_working_object_admin" {
  bucket   = var.named_bucket_names.ost_1_working
  role     = "roles/storage.objectUser"
  for_each = toset(["user:samara.h.haven@noaa.gov", "user:murali.moore@noaa.gov", "user:louisa.li@noaa.gov"])
  member   = each.key
}

# --- Repository Source Readers ---

resource "google_project_iam_member" "proj_admin_source_repo_readers" {
  project = var.project_id
  role    = "roles/source.reader"
  for_each = toset(distinct(concat(
    ["user:chris.angiel@noaa.gov", "user:rajinder.gill@noaa.gov"],
    var.additional_source_repo_readers,
  )))
  member = each.key
}

################################################################################
# SECTION 10: GLOBAL BUCKET VIEWERS
# Granting wide read access to buckets for NOAA users.
################################################################################

# Open up bucket listership and metadata viewership
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

# Specific exemption: This SA is added to nefsc-1 specifically, not via the loop below.
resource "google_storage_bucket_iam_member" "nefsc_1_extra_sa_viewer" {
  count  = var.aa_ncsi_service_account_member != "" ? 1 : 0
  bucket = "nefsc-1"
  role   = "roles/storage.objectViewer"
  member = var.aa_ncsi_service_account_member
}

# --- Dynamic Bucket Permissions (Optimized) ---
# Replaces individual resource blocks for every bucket to reduce code duplication.

locals {
  all_noaa_objectviewer_buckets = toset(concat(
    var.standard_bucket_names,
    var.additional_bucket_objectviewer_buckets,
  ))

  all_noaa_objectviewer_bindings = {
    for pair in setproduct(tolist(local.all_noaa_objectviewer_buckets), toset(var.bucket_users)) :
    "${pair[0]}|${pair[1]}" => {
      bucket = pair[0]
      member = pair[1]
    }
  }
}

resource "google_storage_bucket_iam_member" "all_noaa_bucket_objects_viewer" {
  for_each = local.all_noaa_objectviewer_bindings

  bucket = each.value.bucket
  role   = "roles/storage.objectViewer"
  member = each.value.member
}
