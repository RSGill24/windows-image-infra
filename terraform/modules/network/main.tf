resource "google_project_service" "dns_service" {
  project = var.project_id
  service = var.dns_service_name
}

resource "google_dns_policy" "dns_logging" {
  depends_on     = [google_project_service.dns_service]
  name           = var.dns_policy_name
  project        = var.project_id
  enable_logging = true
  networks {
    network_url = google_compute_network.app_network.id
  }
}

resource "google_compute_network" "app_network" {
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "app_subnet1" {
  name                     = var.subnet_app1
  ip_cidr_range            = var.app_subnet1_cidr
  project                  = var.project_id
  region                   = var.region
  private_ip_google_access = true
  network                  = google_compute_network.app_network.id
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "app_subnet2" {
  name                     = var.subnet_app2
  ip_cidr_range            = var.app_subnet2_cidr
  project                  = var.project_id
  region                   = var.region
  private_ip_google_access = true
  network                  = google_compute_network.app_network.id
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "db_subnet1" {
  name                     = var.subnet_db1
  ip_cidr_range            = var.db_subnet1_cidr
  project                  = var.project_id
  region                   = var.region
  private_ip_google_access = true
  network                  = google_compute_network.app_network.id
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "batch_subnet" {
  name                     = var.subnet_batch
  ip_cidr_range            = var.batch_subnet_cidr
  project                  = var.project_id
  region                   = var.region
  private_ip_google_access = true
  network                  = google_compute_network.app_network.id
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "iap_to_ssh" {
  name          = "ingress-allow-iap-to-ssh"
  network       = google_compute_network.app_network.id
  project       = var.project_id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.iap_source_range]
  allow {
    protocol = "tcp"
    ports    = var.iap_ssh_ports
  }
  log_config { metadata = "INCLUDE_ALL_METADATA" }
}

resource "google_compute_firewall" "iap_to_rdp" {
  name          = "ingress-allow-iap-to-rdp"
  network       = google_compute_network.app_network.id
  project       = var.project_id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.iap_source_range]
  allow {
    protocol = "tcp"
    ports    = var.iap_rdp_ports
  }
  log_config { metadata = "INCLUDE_ALL_METADATA" }
}

resource "google_compute_firewall" "iap_to_winrm_ssl" {
  name          = "ingress-allow-iap-to-winrm-ssl"
  network       = google_compute_network.app_network.id
  project       = var.project_id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.iap_source_range]
  allow {
    protocol = "tcp"
    ports    = var.iap_winrm_ports
  }
  log_config { metadata = "INCLUDE_ALL_METADATA" }
}

resource "google_compute_firewall" "user_vm_subnet1_traffic" {
  name          = "ingress-user-vm-subnet1"
  network       = google_compute_network.app_network.id
  project       = var.project_id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.app_subnet1_cidr, var.app_subnet2_cidr]
  allow {
    protocol = var.user_vm_protocols
  }
  log_config { metadata = "INCLUDE_ALL_METADATA" }
}

resource "google_compute_router" "app_router" {
  name    = var.router_name
  region  = var.region
  network = google_compute_network.app_network.id
  project = var.project_id
  bgp {
    asn = var.cloud_router_asn
  }
}

resource "google_compute_router_nat" "nat" {
  name                               = var.nat_name
  router                             = google_compute_router.app_router.name
  project                            = var.project_id
  region                             = google_compute_router.app_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
