terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }

  backend "gcs" {
    bucket = "big-mender-473219-r2-tf-state"
    prefix = "windows-image-builder"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
