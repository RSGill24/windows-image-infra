terraform {
  backend "gcs" {
    bucket = "tf-local-ggn-nmfs-pamdata-dev-1"
    prefix = "terraform/state"
  }
}