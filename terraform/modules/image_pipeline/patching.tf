resource "google_os_config_patch_deployment" "ubuntu_force_reboot_patch" {
  patch_deployment_id = "ubuntu-force-reboot-patch-weds-7utc"
  project             = var.project_id

  instance_filter {
    group_labels {
      labels = {
        noaa_project_id                     = var.project_id
        ubuntu_force_reboot_patch_weds_7utc = true
      }
    }
  }

  patch_config {
    reboot_config = "DEFAULT"
    apt { type = "DIST" }
  }

  duration = var.ubuntu_patch_duration

  recurring_schedule {
    time_zone { id = "UTC" }
    time_of_day {
      hours   = var.ubuntu_patch_hour
      minutes = var.ubuntu_patch_minute
      seconds = 0
      nanos   = 0
    }
    weekly {
      day_of_week = var.ubuntu_patch_day
    }
  }

  rollout {
    mode = "CONCURRENT_ZONES"
    disruption_budget { percentage = 100 }
  }
}

resource "google_os_config_patch_deployment" "windows_force_reboot_patch" {
  patch_deployment_id = "windows-force-reboot-patch-15th"
  project             = var.project_id

  patch_config {
    reboot_config = "DEFAULT"
  }

  instance_filter {
    group_labels {
      labels = {
        noaa_project_id                 = var.project_id
        windows_force_reboot_patch_15th = true
      }
    }
  }

  duration = var.windows_patch_duration

  recurring_schedule {
    time_zone { id = "UTC" }
    time_of_day {
      hours   = var.windows_patch_hour
      minutes = var.windows_patch_minute
      seconds = 0
      nanos   = 0
    }
    monthly {
      month_day = var.windows_patch_month_day
    }
  }

  rollout {
    mode = "CONCURRENT_ZONES"
    disruption_budget { percentage = 100 }
  }
}

resource "google_compute_resource_policy" "dormant_patch_boot" {
  name        = "dormant-patch-boot"
  region      = var.region
  project     = var.project_id
  description = "Boot at start of hour for patching"
  instance_schedule_policy {
    vm_start_schedule { schedule = var.dormant_patch_boot_schedule }
    time_zone = "UTC"
  }
}

resource "google_compute_resource_policy" "patch_boot_shutdown" {
  name        = "patch-boot-shutdown"
  region      = var.region
  project     = var.project_id
  description = "Boot at start of hour for patching and shut down two hours later"
  instance_schedule_policy {
    vm_start_schedule { schedule = var.patch_boot_shutdown_start_schedule }
    vm_stop_schedule  { schedule = var.patch_boot_shutdown_stop_schedule }
    time_zone = "UTC"
  }
}
