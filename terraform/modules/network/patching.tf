#docker dev workstation: patch strategy will be weekly, with reboot, and will wake up a dormant instance
#to keep it on the schedule.

resource "google_os_config_patch_deployment" "ubuntu_force_reboot_patch_weds_7utc" {
  patch_deployment_id = "ubuntu-force-reboot-patch-weds-7utc"

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

    apt {
      type = "DIST"
    }
  }

  duration = "1800s"

  recurring_schedule {
    time_zone {
      id = "UTC"
    }

    time_of_day {
      hours   = var.ubuntu_patch_hour
      minutes = var.ubuntu_patch_minute
      seconds = 00
      nanos   = 00
    }

    weekly {
      day_of_week = var.ubuntu_patch_day_of_week
    }
  }

  rollout {
    mode = "CONCURRENT_ZONES"

    disruption_budget {
      percentage = 100
    }
  }
}

#windows workstations: Will boot weekly and force restart, but will do so on Tuesday night so critical updates
#will be applied within 24 hrs of patch tuesday.

resource "google_os_config_patch_deployment" "windows_force_reboot_patch_15th" {
  patch_deployment_id = "windows-force-reboot-patch-15th"

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

  duration = "5400s"

  recurring_schedule {
    time_zone {
      id = "UTC"
    }

    time_of_day {
      hours   = var.windows_patch_hour
      minutes = var.windows_patch_minute
      seconds = 00
      nanos   = 00
    }

    #weekly {
    #  day_of_week = "WEDNESDAY"
    #}

    monthly {
      month_day = var.windows_patch_month_day
    }
  }

  rollout {
    mode = "CONCURRENT_ZONES"

    disruption_budget {
      percentage = 100
    }
  }
}

#resource policy for above to enforce the boot. Instances have a startup script to automatically shut them
#back off if they were booted at the unusual patch hour (for US, late evening tues/ early morning weds). True for both
#linux and windows instances.

resource "google_compute_resource_policy" "dormant-patch-boot" {
  name        = "dormant-patch-boot"
  region      = var.region1
  description = "boot at start of hour for patching"

  instance_schedule_policy {
    vm_start_schedule {
      schedule = var.linux_patch_schedule
    }

    time_zone = "UTC"
  }
}

#GCP windows patching seems to interrupt the startup behavior to detect a start within the window and schedule a
#shutdown, so for windows VMs just mandate a shutdown

resource "google_compute_resource_policy" "patch-boot-shutdown" {
  name        = "patch-boot-shutdown"
  region      = var.region1
  description = "boot at start of hour for patching and shut down two hours later"

  instance_schedule_policy {
    vm_start_schedule {
      schedule = var.windows_patch_schedule
    }

    vm_stop_schedule {
      schedule = var.windows_patch_stop_schedule
    }

    time_zone = "UTC"
  }
}

