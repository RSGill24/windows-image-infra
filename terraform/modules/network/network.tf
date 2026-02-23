# DNS Logging Policy as required by compliance policy - Activate API.
resource "google_project_service" "dns_service" {
  project = var.project_id
  service = "dns.googleapis.com"
}

# DNS Logging Policy as required for compliance.
resource "google_dns_policy" "dns_logging" {
  depends_on     = [google_project_service.dns_service]
  name           = var.dns_policy_name
  project        = var.project_id
  enable_logging = true

  networks {
    network_url = google_compute_network.app_network.id
  }
}

################### app network and subnet

resource "google_compute_network" "app_network" {
  name                    = var.app_network_name
  project                 = var.project_id
  auto_create_subnetworks = false
}

resource "google_compute_firewall" "iap_to_ssh" {
  name    = var.iap_ssh_firewall_name
  network = google_compute_network.app_network.id
  project = var.project_id

  direction = "INGRESS"
  priority  = 1000

  # Cloud IAP's TCP forwarding netblock
  source_ranges = var.iap_source_ranges

  allow {
    protocol = "tcp"
    ports    = [22]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "iap_to_rdp" {
  name    = var.iap_rdp_firewall_name
  network = google_compute_network.app_network.id
  project = var.project_id

  direction = "INGRESS"
  priority  = 1000

  # Cloud IAP's TCP forwarding netblock
  source_ranges = var.iap_source_ranges

  allow {
    protocol = "tcp"
    ports    = [3389]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# enables packer to run winrm over ssl port
resource "google_compute_firewall" "iap_to_winrm_ssl" {
  name    = var.iap_winrm_firewall_name
  network = google_compute_network.app_network.id
  project = var.project_id

  direction = "INGRESS"
  priority  = 1000

  # Cloud IAP's TCP forwarding netblock
  source_ranges = var.iap_source_ranges

  allow {
    protocol = "tcp"
    ports    = [5986]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_router" "app_router" {
  name    = var.router_name
  region  = var.region1
  network = google_compute_network.app_network.id
  project = var.project_id

  bgp {
    asn = 64514
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

# app subnet
resource "google_compute_subnetwork" "app_subnet1" {
  name                     = var.app_subnet1_name
  ip_cidr_range            = var.app_subnet1_cidr
  project                  = var.project_id
  region                   = var.region1
  private_ip_google_access = true
  network                  = google_compute_network.app_network.id

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# expand pam-wv range out another 64 IPs
resource "google_compute_subnetwork" "app_subnet2" {
  name                     = var.app_subnet2_name
  ip_cidr_range            = var.app_subnet2_cidr
  project                  = var.project_id
  region                   = var.region1
  private_ip_google_access = true
  network                  = google_compute_network.app_network.id

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "user_vm_subnet1_traffic" {
  name    = var.east_west_firewall_name
  network = google_compute_network.app_network.id
  project = var.project_id

  direction = "INGRESS"
  priority  = 1000

  # app subnet range
  source_ranges = [var.app_subnet1_cidr, var.app_subnet2_cidr]

  allow {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

################### db subnet

resource "google_compute_subnetwork" "db_subnet1" {
  name                     = var.db_subnet1_name
  ip_cidr_range            = var.db_subnet1_cidr
  project                  = var.project_id
  region                   = var.region1
  private_ip_google_access = true
  network                  = google_compute_network.app_network.id

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

################### batch subnet

resource "google_compute_subnetwork" "batch_subnet" {
  name                     = var.batch_subnet_name
  ip_cidr_range            = var.batch_subnet_cidr
  project                  = var.project_id
  region                   = var.region1
  private_ip_google_access = true
  network                  = google_compute_network.app_network.id

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

