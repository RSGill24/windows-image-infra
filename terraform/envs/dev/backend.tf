terraform {
  backend "gcs" {
    bucket = "tf-local-ggn-nmfs-pamdata-prod-1" # or dev equivalent
    prefix = "terraform/state"
  }
}