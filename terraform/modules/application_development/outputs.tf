output "app_dev_instance_name" {
  value = google_compute_instance.app_dev_server1.name
}

output "docker_repo_id" {
  value = google_artifact_registry_repository.pamdata_docker_repo.repository_id
}
