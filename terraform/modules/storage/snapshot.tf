#create snapshot policy for MY instance (and any one else that wants one, I suppose)
#the GPU machine has a lot of / fragile dependencies, so good to keep it backed up.
#
#snapshot every 3 days, better, don't care as much about new data, just keeping the state intact from
#point where it worked.

resource "google_compute_resource_policy" "dwoodrich_gpu_snap_sched" {
  name   = var.snapshot_policy_name
  region = var.region1

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "04:00"
      }
    }

    retention_policy {
      max_retention_days    = 14
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
  }
}

resource "google_compute_disk_resource_policy_attachment" "win_fs_boot_disk_snap_attachment" {
  project = var.project_id
  name    = google_compute_resource_policy.dwoodrich_gpu_snap_sched.name
  disk    = var.snapshot_target_disk_name
  zone    = var.zone1
}

