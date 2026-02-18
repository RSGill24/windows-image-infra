terraform {
  backend "gcs" {
    bucket = "tf-local-ggn-nmfs-pamdata-prod-1" 
  }
}