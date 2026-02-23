packer {
  required_plugins {
    googlecompute = {
      version = "1.1.6"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "packer_user_password" {
  type      = string
  default   = env("PACKER_PW")
  sensitive = true
}

variable "source_image" {
  type    = string
  default = env("SRC_IMG_NAME")
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

variable "image_family" {
  type = string
}

variable "machine_type" {
  type = string
}

variable "zone" {
  type = string
}

variable "hardening_source_dir" {
  type = string
}

variable "hardening_target_dir" {
  type = string
}

variable "hardening_entry_script" {
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
  winrm_use_ssl           = true
  winrm_insecure          = true
  service_account_email   = var.service_account_email
  zone                    = var.zone
  enable_secure_boot          = false
  enable_integrity_monitoring = false
  enable_vtpm                 = false
  disk_size                   = 250

  image_family = var.image_family
  image_name   = "pww-disa-${var.source_image}-hardened-patched-{{timestamp}}"
  machine_type = var.machine_type
}

build {
  sources = ["sources.googlecompute.update_pam_ww"]

  provisioner "powershell" {
    inline = [
      "Get-WindowsUpdate -Install -AcceptAll"
    ]

    elevated_user     = "packer_user"
    elevated_password = var.packer_user_password
  }

  provisioner "file" {
    source      = var.hardening_source_dir
    destination = var.hardening_target_dir
  }

  provisioner "powershell" {
    inline = [
      "cd ${var.hardening_target_dir}",
      "./${var.hardening_entry_script}"
    ]

    elevated_user     = "packer_user"
    elevated_password = var.packer_user_password
  }
}

