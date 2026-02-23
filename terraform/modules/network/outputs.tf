output "app_network_id" {
  value = google_compute_network.app_network.id
}

output "app_subnet1_self_link" {
  value = google_compute_subnetwork.app_subnet1.self_link
}

output "app_subnet2_self_link" {
  value = google_compute_subnetwork.app_subnet2.self_link
}

output "db_subnet1_id" {
  value = google_compute_subnetwork.db_subnet1.id
}
