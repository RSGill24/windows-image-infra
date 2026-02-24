environment                      = "prod"
project_id                       = "ggn-nmfs-pamdata-prod-1"
region1                          = "us-east4"
zone1                            = "us-east4-c"
application_id                   = "pamdata"
lineoffice                       = "nmfs"
system_id                        = "noaa4000"
taskorder                        = "13051420fnffk0123"
bucket_prefix                    = "pamdata"
artifact_bucket                  = "tflocal-ggn-nmfs-pamdata-prod-1"
auto_shutdown                    = true
enable_audit                     = true
cloudbuild_repo_uri              = "https://source.developers.google.com/p/ggn-nmfs-pamdata-prod-1/r/tf-repo-pamdata"
cloudbuild_branch_ref            = "refs/heads/main"
cloudbuild_schedule              = "0 0 16 * *"
cloudbuild_time_zone             = "Etc/UTC"
cloudbuild_filename              = "packer/cloudbuild.yml"
cloudsql_psc_service_attachment  = "REPLACE_WITH_DEV_ATTACHMENT"
bq_compliance_dataset_id         = "pam_wv_instance_controls"
bq_compliance_table_id           = "pam-wv-instance-controls-table"
gcs_read_logs_dataset_id         = "gcs_read_logs"
ds_image_project_id              = "ggn-nmfs-pamdata-prod-1"
windows_workstation_image_project_id = "ggn-nmfs-pamdata-prod-1"
windows_template_image_project_id    = "ggn-nmfs-pamdata-prod-1"
gpu_boot_disk_project_id             = "ggn-nmfs-pamdata-prod-1"
windows_gpu_type                 = "https://www.googleapis.com/compute/v1/projects/ggn-nmfs-pamdata-prod-1/zones/us-east4-c/acceleratorTypes/nvidia-tesla-t4"
windows_custom_boot_disk_source  = "projects/ggn-nmfs-pamdata-prod-1/zones/us-east4-c/disks/ins-copy-eb"
enable_gpu_workstation           = true
gpu_boot_disk_name               = "dwoodrich-gpu3"
enable_custom_boot_disk_instance = true
enable_snapshot_disk_attachment  = true
windows_template_instance_name   = "lastest-pam-ww-template-instance"
windows_patch_schedule           = "0 22 15 * *"
windows_patch_stop_schedule      = "59 23 15 * *"
linux_patch_schedule             = "0 7 * * 3"

pamdata_admin = [
  "user:daniel.woodrich@noaa.gov",
  "user:jeffrey.walker@noaa.gov"
]

pamdata_supervisors = [
  "user:sofie.vanparijs@noaa.gov",
  "user:rebecca.vanhoeck@noaa.gov"
]

app_developers = [
  "user:daniel.woodrich@noaa.gov"
]

pamdata_transfer_appliance_admins = [
  "user:rebecca.vanhoeck@noaa.gov"
]

pamdata_transfer_appliance_users = [
  "user:thomas.sejkora@noaa.gov",
  "user:daniel.woodrich@noaa.gov"
]

nefsc_minke_detector_users = [
  "user:daniel.woodrich@noaa.gov",
  "user:lindsey.transue@noaa.gov",
  "serviceAccount:composer-sa1@ggn-nmfs-pamarc-dev-1.iam.gserviceaccount.com"
]

nefsc_humpback_detector_users = [
  "user:daniel.woodrich@noaa.gov",
  "user:lindsey.transue@noaa.gov",
  "serviceAccount:composer-sa1@ggn-nmfs-pamarc-dev-1.iam.gserviceaccount.com"
]

afsc_instinct_users = [
  "user:daniel.woodrich@noaa.gov",
  "serviceAccount:composer-sa1@ggn-nmfs-pamarc-dev-1.iam.gserviceaccount.com",
  "serviceAccount:afsc-instinct@ggn-nmfs-pamdata-prod-1.iam.gserviceaccount.com"
]

bucket_users = [
  "domain:noaa.gov",
  "serviceAccount:app-dev-sa@ggn-nmfs-pamdata-prod-1.iam.gserviceaccount.com",
  "serviceAccount:windows-workstation-sa@ggn-nmfs-pamdata-prod-1.iam.gserviceaccount.com"
]

pam_ww_users1 = [
  "user:daniel.woodrich@noaa.gov"
]

data_buckets_map = {
  "afsc-1" = {
    data_authority = "user:catherine.berchok@noaa.gov"
    data_admins    = ["user:daniel.woodrich@noaa.gov", "user:catherine.berchok@noaa.gov"]
    all_users      = ["group:nmfs.afsc.nml.acoustics@noaa.gov"]
  }
  "nefsc-1" = {
    data_authority = "user:sofie.vanparijs@noaa.gov"
    data_admins    = ["user:julianne.wilder@noaa.gov"]
    all_users      = ["user:sofie.vanparijs@noaa.gov"]
  }
  "pifsc-1" = {
    data_authority = "user:ann.allen@noaa.gov"
    data_admins    = ["user:ann.allen@noaa.gov"]
    all_users      = []
  }
  "swfsc-1" = {
    data_authority = "user:shannon.rankin@noaa.gov"
    data_admins    = ["user:shannon.rankin@noaa.gov"]
    all_users      = []
  }
  "sefsc-1" = {
    data_authority = "user:melissa.soldevilla@noaa.gov"
    data_admins    = ["user:melissa.soldevilla@noaa.gov"]
    all_users      = []
  }
  "sefsc-2" = {
    data_authority = "user:melissa.soldevilla@noaa.gov"
    data_admins    = ["user:melissa.soldevilla@noaa.gov"]
    all_users      = []
  }
}
