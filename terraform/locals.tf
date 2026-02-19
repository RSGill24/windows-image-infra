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


  # ── Derived Resource Names ────────────────────────────────────────────────
  # Naming convention: {prefix}-{environment}-{suffix}
  # Change var.environment in tfvars → all names update automatically

  tf_state_bucket         = "tf-local-${var.project_id}"
  pam_ww_tmp_bucket       = "pam-ww-tmp-${var.project_id}"
  docker_repo_id          = "${var.application_id}-docker-repo"
  pubsub_topic_name       = "run-monthly-rebuilds-${var.environment}"
  scheduler_job_name      = "golden-image-monthly-rebuild-${var.environment}"
  cloudbuild_trigger_name = "golden-image-build-scheduled-${var.environment}"
  packer_sa_account_id    = "packer-builder-sa-${var.environment}"
  ww_sa_account_id        = "windows-workstation-sa"
  app_dev_sa_account_id   = "app-dev-sa"

  # ── Derived Service Account Emails ────────────────────────────────────────
  # Built from project_id — no need to hardcode emails in tfvars
  packer_sa_email  = "${local.packer_sa_account_id}@${var.project_id}.iam.gserviceaccount.com"
  ww_sa_email      = "${local.ww_sa_account_id}@${var.project_id}.iam.gserviceaccount.com"
  app_dev_sa_email = "${local.app_dev_sa_account_id}@${var.project_id}.iam.gserviceaccount.com"

  # Cross-project SAs that are referenced (pamarc project)
  pamarc_dev_composer_sa = "serviceAccount:composer-sa1@ggn-nmfs-pamarc-dev-1.iam.gserviceaccount.com"
  pamarc_prod_run_sa     = "serviceAccount:pamarc-run-sa@ggn-nmfs-pamarc-prod-1.iam.gserviceaccount.com"
  afsc_instinct_sa       = "serviceAccount:afsc-instinct@${var.project_id}.iam.gserviceaccount.com"

  # ── Derived Bucket User List ───────────────────────────────────────────────
  # Automatically includes all project SAs + cross-project SAs
  # Add new SAs here once — propagates everywhere
  computed_bucket_users = concat(
    var.extra_bucket_users,
    [
      "serviceAccount:${local.app_dev_sa_email}",
      "serviceAccount:${local.ww_sa_email}",
      "serviceAccount:nefsc-minke-detector@${var.project_id}.iam.gserviceaccount.com",
      "serviceAccount:nefsc-humpback-detector@${var.project_id}.iam.gserviceaccount.com",
      local.pamarc_dev_composer_sa,
      local.afsc_instinct_sa,
      local.pamarc_prod_run_sa,
    ]
  )

  # ── Resource Policy URLs ───────────────────────────────────────────────────
  # Built from project_id + region — used by compute instances
  patch_boot_shutdown_policy_url = "https://www.googleapis.com/compute/v1/projects/${var.project_id}/regions/${var.region}/resourcePolicies/patch-boot-shutdown"
  dormant_patch_boot_policy_url  = "https://www.googleapis.com/compute/v1/projects/${var.project_id}/regions/${var.region}/resourcePolicies/dormant-patch-boot"

  # ── GPU Accelerator Full URL ───────────────────────────────────────────────
  gpu_accelerator_url = "https://www.googleapis.com/compute/v1/projects/${var.project_id}/zones/${var.zone}/acceleratorTypes/${var.gpu_accelerator_type}"

  # ── CloudBuild Source Repo URL ─────────────────────────────────────────────
  source_repo_url = "https://source.developers.google.com/p/${var.project_id}/r/${var.source_repo_name}"

  # ── Patch Deployment IDs ───────────────────────────────────────────────────
  ubuntu_patch_deployment_id  = "ubuntu-force-reboot-patch-weds-7utc-${var.environment}"
  windows_patch_deployment_id = "windows-force-reboot-patch-15th-${var.environment}"

  # ── Network Resource Names ─────────────────────────────────────────────────
  network_name = "${var.network_prefix}-${var.environment}"
  router_name  = "${var.network_prefix}-router-${var.environment}"
  nat_name     = "${var.network_prefix}-nat-${var.environment}"
  subnet_app1  = "${var.network_prefix}-app-subnet1-${var.environment}"
  subnet_app2  = "${var.network_prefix}-app-subnet2-${var.environment}"
  subnet_db1   = "${var.network_prefix}-db-subnet1-${var.environment}"
  subnet_batch = "${var.network_prefix}-batch-subnet-${var.environment}"

}
