resource "google_compute_resource_policy" "gpu_snap_sched" {
  name    = var.snapshot_policy_name
  region  = var.region
  project = var.project_id

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = var.snapshot_days_in_cycle
        start_time    = var.snapshot_start_time
      }
    }
    retention_policy {
      max_retention_days    = var.snapshot_max_retention_days
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
  }
}

resource "google_compute_disk_resource_policy_attachment" "gpu_disk_snap_attachment" {
  project = var.project_id
  name    = google_compute_resource_policy.gpu_snap_sched.name
  disk    = var.gpu_disk_name
  zone    = var.zone
}
