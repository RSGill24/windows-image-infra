#test sql, network, dns resources for cloud sql test in pamdata.
#
#carve off a new subnet for dbs on private network. Do on network .tf even if it is test as this is a prod network.
#
#db resources

resource "google_sql_database_instance" "pam_working_detections_db_instance" {
  name                = "pam-working-detections-db-instance"
  project             = var.project_id
  region              = var.region1
  database_version    = "POSTGRES_14"
  deletion_protection = "true"

  settings {
    tier              = "db-custom-4-16384" # was: "db-custom-8-32768"
    activation_policy = "ALWAYS"
    availability_type = "ZONAL"

    user_labels = {
      environment        = var.environment
      noaa_fismaid       = var.system_id
      noaa_lineoffice    = var.lineoffice
      noaa_taskorder     = var.taskorder
      noaa_environment   = var.environment
      noaa_applicationid = var.application_id
      noaa_project_id    = var.project_id
    }

    ip_configuration {
      psc_config {
        psc_enabled               = true
        allowed_consumer_projects = var.allowed_consumer_projects
      }

      ipv4_enabled = false
      ssl_mode     = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = "true"
      point_in_time_recovery_enabled = "true"
      start_time                     = "15:00"
      location                       = var.region1
    }

    location_preference {
      zone = var.zone1
    }

    maintenance_window {
      day          = "7"
      hour         = "4"
      update_track = "stable"
    }

    disk_autoresize = "true" # this gets annoying with terraform, good to manage manually for billing.
    # however, turn on temporarily to migrate in afsc db
    disk_size = "287"
    disk_type = "PD_HDD"

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    database_flags {
      name  = "log_duration"
      value = "on"
    }

    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }

    database_flags {
      name  = "log_temp_files"
      value = "0"
    }

    database_flags {
      name  = "log_statement"
      value = "ddl"
    }

    database_flags {
      name  = "work_mem"
      value = "2097152"
    }

    # More aggressively use resources:
    database_flags {
      name  = "maintenance_work_mem"
      value = "4194304"
    }

    database_flags {
      name  = "temp_file_limit"
      value = "2147483647"
    }

    database_flags {
      name  = "autovacuum_vacuum_scale_factor"
      value = "0"
    }

    database_flags {
      name  = "autovacuum_vacuum_threshold"
      value = "25000"
    }

    database_flags {
      name  = "autovacuum_analyze_scale_factor"
      value = "0"
    }

    database_flags {
      name  = "autovacuum_analyze_threshold"
      value = "25000"
    }

    database_flags {
      name  = "autovacuum_naptime"
      value = "7200"
    }

  }
}

resource "google_compute_address" "psc_endpoint_ip" {
  name         = var.psc_endpoint_ip_name
  subnetwork   = var.db_subnet1_id
  address_type = "INTERNAL"
  region       = var.region1
  project      = var.project_id
}

resource "google_compute_forwarding_rule" "psc_to_cloudsql_endpoint" {
  name                  = var.psc_forwarding_rule_name
  project               = var.project_id
  region                = var.region1
  load_balancing_scheme = "INTERNAL"
  network               = var.app_network_id
  subnetwork            = var.db_subnet1_id
  ip_address            = google_compute_address.psc_endpoint_ip.self_link

  # Should match the SQL service attachment, e.g. found with:
  #   gcloud sql instances describe pam-working-detections-db-instance
  target = var.cloudsql_psc_service_attachment

  depends_on = [
    google_sql_database_instance.pam_working_detections_db_instance,
  ]
}

# Define the Private DNS Managed Zone (optional)
# resource "google_dns_managed_zone" "sql_psc_private_zone" {
#   name        = "sql-psc-dns-zone"
#   dns_name    = "us-east4.sql.goog."  # must end with a period
#   description = "Private DNS zone for Cloud SQL PSC endpoints"
#   visibility  = "private"
#
#   private_visibility_config {
#     networks {
#       network_url = google_compute_network.app_network.self_link
#     }
#   }
# }

# Define the A record for the PSC endpoint (optional)
# resource "google_dns_record_set" "sql_psc_a_record" {
#   name         = "<INSTANCE_DNS_NAME_FROM_GCLOUD>."
#   managed_zone = google_dns_managed_zone.sql_psc_private_zone.name
#   type         = "A"
#   ttl          = 300
#   rrdatas      = [google_compute_address.psc_endpoint_ip.address]
# }


