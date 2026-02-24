# bucket for pam users to exchange data.
# free for all for data transfer; no permissions enforced here.
locals {
  # Canonical naming pattern requested for bucket resources.
  bucket_name_prefix = "${var.bucket_prefix}-${var.environment}"

  # Artifact bucket target for metadata objects.
  artifact_bucket_name = trimspace(var.artifact_bucket) != "" ? var.artifact_bucket : local.bucket_name_prefix

  named_bucket_names = {
    pam_ww_tmp                 = "${local.bucket_name_prefix}-pam-ww-tmp"
    app_intermediates          = "${local.bucket_name_prefix}-app-intermediates"
    app_outputs                = "${local.bucket_name_prefix}-app-outputs"
    nefsc_1_detector_output    = "nefsc-1-detector-output"
    nefsc_1_ancillary_data     = "nefsc-1-ancillary-data"
    nefsc_1_pab                = "${local.bucket_name_prefix}-nefsc-1-pab"
    pifsc_1_detector_output    = "${local.bucket_name_prefix}-pifsc-1-detector-output"
    pifsc_1_working            = "${local.bucket_name_prefix}-pifsc-1-working"
    afsc_1_working             = "${local.bucket_name_prefix}-afsc-1-working"
    swfsc_1_working            = "${local.bucket_name_prefix}-swfsc-1-working"
    sefsc_1_working            = "${local.bucket_name_prefix}-sefsc-1-working"
    sefsc_2_working            = "${local.bucket_name_prefix}-sefsc-2-working"
    ost_1_working              = "${local.bucket_name_prefix}-ost-1-working"
    afsc_1_temp                = "${local.bucket_name_prefix}-afsc-1-temp"
    nmfs_collaborative_working = "${local.bucket_name_prefix}-nmfs-collaborative-working"
  }

  common_bucket_labels = {
    noaa_fismaid       = var.system_id
    noaa_lineoffice    = var.lineoffice
    noaa_taskorder     = var.taskorder
    noaa_environment   = var.environment
    noaa_applicationid = var.application_id
    noaa_project_id    = var.project_id
  }
}

resource "google_storage_bucket" "pam_ww_tmp" {
  name     = local.named_bucket_names.pam_ww_tmp
  location = var.region1

  uniform_bucket_level_access = true

  labels = merge(local.common_bucket_labels, {
    bucket_name = local.named_bucket_names.pam_ww_tmp
  })

  autoclass {
    enabled = true
  }

  # lifecycle_rule {
  #   condition { age = 0 }
  #   action { type = "Delete" }
  # }
}

# app intermediate bucket. ideally subdivide into:
# gs://${local.named_bucket_names.app_intermediates}/[APP_NAME]
resource "google_storage_bucket" "pamdata_app_intermediates" {
  name     = local.named_bucket_names.app_intermediates
  location = var.region1

  uniform_bucket_level_access = true

  labels = merge(local.common_bucket_labels, {
    bucket_name = local.named_bucket_names.app_intermediates
  })

  autoclass {
    enabled = true
  }
}

# app outputs bucket. ideally subdivide into:
# gs://${local.named_bucket_names.app_outputs}/[APP_NAME]
resource "google_storage_bucket" "pamdata_app_outputs" {
  name     = local.named_bucket_names.app_outputs
  location = var.region1

  uniform_bucket_level_access = true

  labels = merge(local.common_bucket_labels, {
    bucket_name = local.named_bucket_names.app_outputs
  })

  autoclass {
    enabled = true
  }
}

# all data buckets
resource "google_storage_bucket" "data_buckets" {
  for_each = var.data_buckets_map

  name     = each.key
  location = var.region1

  uniform_bucket_level_access = true

  labels = merge(local.common_bucket_labels, {
    data_authority = replace(replace(lower(each.value.data_authority), "@", "_"), ".", "_")
    bucket_name    = each.key
  })

  autoclass {
    enabled = true
  }

  # Placeholder: allow optional lifecycle tuning per bucket in future.
  # lifecycle {
  #   ignore_changes = [autoclass]
  # }
}

# nefsc working bucket
resource "google_storage_bucket" "nefsc_1_pab" {
  name     = local.named_bucket_names.nefsc_1_pab
  location = var.region1

  uniform_bucket_level_access = true

  labels = merge(local.common_bucket_labels, {
    bucket_name = local.named_bucket_names.nefsc_1_pab
  })

  autoclass {
    enabled = true
  }
}

resource "google_storage_bucket" "pifsc_1_detector_output" {
  name     = local.named_bucket_names.pifsc_1_detector_output
  location = var.region1

  uniform_bucket_level_access = true

  labels = merge(local.common_bucket_labels, {
    bucket_name = local.named_bucket_names.pifsc_1_detector_output
  })

  autoclass {
    enabled = true
  }
}

resource "google_storage_bucket" "pifsc_1_working" {
  name     = local.named_bucket_names.pifsc_1_working
  location = var.region1

  uniform_bucket_level_access = true

  labels = merge(local.common_bucket_labels, {
    bucket_name = local.named_bucket_names.pifsc_1_working
  })

  autoclass {
    enabled = true
  }
}

resource "google_storage_bucket" "afsc_1_working" {
  name     = local.named_bucket_names.afsc_1_working
  location = var.region1

  uniform_bucket_level_access = true

  labels = merge(local.common_bucket_labels, {
    bucket_name = local.named_bucket_names.afsc_1_working
  })

  autoclass {
    enabled = true
  }
}

resource "google_storage_bucket" "swfsc_1_working" {
  name     = local.named_bucket_names.swfsc_1_working
  location = var.region1

  uniform_bucket_level_access = true

  labels = merge(local.common_bucket_labels, {
    bucket_name = local.named_bucket_names.swfsc_1_working
  })

  autoclass {
    enabled = true
  }
}

resource "google_storage_bucket" "sefsc_1_working" {
  name     = local.named_bucket_names.sefsc_1_working
  location = var.region1

  uniform_bucket_level_access = true

  labels = merge(local.common_bucket_labels, {
    bucket_name = local.named_bucket_names.sefsc_1_working
  })

  autoclass {
    enabled = true
  }
}

resource "google_storage_bucket" "sefsc_2_working" {
  name     = local.named_bucket_names.sefsc_2_working
  location = var.region1

  uniform_bucket_level_access = true

  labels = merge(local.common_bucket_labels, {
    bucket_name = local.named_bucket_names.sefsc_2_working
  })

  autoclass {
    enabled = true
  }
}

resource "google_storage_bucket" "ost_1_working" {
  name     = local.named_bucket_names.ost_1_working
  location = var.region1

  uniform_bucket_level_access = true

  labels = merge(local.common_bucket_labels, {
    bucket_name = local.named_bucket_names.ost_1_working
  })

  autoclass {
    enabled = true
  }
}

# for pngs and decimated data. autodelete 6 months after creation.
resource "google_storage_bucket" "afsc_1_temp" {
  name     = local.named_bucket_names.afsc_1_temp
  location = var.region1

  uniform_bucket_level_access = true

  labels = merge(local.common_bucket_labels, {
    bucket_name = local.named_bucket_names.afsc_1_temp
  })

  autoclass {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 180
    }

    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket" "nmfs_collaborative_working" {
  name     = local.named_bucket_names.nmfs_collaborative_working
  location = var.region1

  uniform_bucket_level_access = true

  labels = merge(local.common_bucket_labels, {
    bucket_name = local.named_bucket_names.nmfs_collaborative_working
  })

  autoclass {
    enabled = true
  }
}

# custom accounting of buckets used by pam-ww mount logic.
resource "google_storage_bucket_object" "data_buckets_list" {
  bucket  = local.artifact_bucket_name
  name    = "cloud_variables/data_bucket_list.txt"
  content = join("\n", keys(var.data_buckets_map))
}

resource "google_storage_bucket_object" "exclude_buckets_list" {
  bucket = local.artifact_bucket_name
  name   = "cloud_variables/exclude_bucket_list.txt"
  content = join("\n", [
    local.artifact_bucket_name,
    local.named_bucket_names.app_intermediates,
  ])
}
