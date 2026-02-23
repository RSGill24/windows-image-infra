packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "packer_user_password" {
  type      = string
  sensitive = true
}

variable "project_id" {
  type = string
}

variable "source_image_project_id" {
  type = string
}

variable "source_image_family" {
  type = string
}

variable "service_account_email" {
  type = string
}

variable "zone" {
  type = string
}

variable "subnetwork" {
  type = string
}

variable "network_project_id" {
  type = string
}

variable "image_description" {
  type = string
}

variable "image_family" {
  type = string
}

variable "image_name_prefix" {
  type = string
}

source "googlecompute" "update_pam_ww" {
  project_id              = var.project_id
  use_iap                 = true
  source_image_project_id = [var.source_image_project_id]
  source_image_family     = var.source_image_family
  communicator            = "winrm"
  winrm_username          = "packer_user"
  winrm_password          = var.packer_user_password
  service_account_email   = var.service_account_email
  winrm_use_ssl           = true
  winrm_insecure          = true
  zone                    = var.zone
  subnetwork              = var.subnetwork
  omit_external_ip        = true
  use_internal_ip         = true
  network_project_id      = var.network_project_id
  image_description       = var.image_description
  enable_secure_boot          = false
  enable_integrity_monitoring = false
  enable_vtpm                 = false
  disk_size                   = 250
  image_family                = var.image_family
  image_name                  = "${var.image_name_prefix}-{{timestamp}}"
}

build {
  sources = ["sources.googlecompute.update_pam_ww"]

  provisioner "powershell" {
    inline = [
      "Get-WindowsUpdate -Install -AutoReboot -AcceptAll"
    ]

    elevated_user     = "packer_user"
    elevated_password = var.packer_user_password
  }

  provisioner "windows-restart" {
    restart_timeout = "15m"
  }

  provisioner "powershell" {
    inline = [
      "Get-WindowsUpdate -Install -AcceptAll"
    ]

    elevated_user     = "packer_user"
    elevated_password = var.packer_user_password
  }

  provisioner "powershell" {
    inline = [
      "shutdown /s /f /t 0"
    ]
  }
}

