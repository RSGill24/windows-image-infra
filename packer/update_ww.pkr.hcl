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

# openssl rand -base64 16 ; something like this can generate random pw for first time. manually apply it to
# packer_user account on the image and GCP secret manager

# to update the image and apply any terraform changes (the most obvious event would be when creating new instances)
# packer build -var packer_user_password=$(gcloud secrets versions access latest --secret="packer_user_password") update_ww.pkr.hcl && terraform apply
#
# to rotate password:
# spawn a new instance (or use a template instance you've persisted), reset pw on that instance, provide a new key value to packer_user_password, and save
# that instance as the latest image in the pam-windows-workstation family.
# then, run above again to use the new pw which will draw from the

# this time, specify oslogin and iap for ssh
source "googlecompute" "update-pam-ww" {
  project_id              = "ggn-nmfs-pamdata-prod-1"
  use_iap                 = true
  source_image_project_id = ["ggn-nmfs-pamdata-prod-1"]
  source_image_family     = "pam-windows-workstation"
  communicator   = "winrm"
  winrm_username = "packer_user"
  winrm_password = var.packer_user_password
  service_account_email = "windows-workstation-sa@ggn-nmfs-pamdata-prod-1.iam.gserviceaccount.com"
  winrm_use_ssl  = true
  winrm_insecure = true
  zone          = "us-east4-c"
  subnetwork    = "app-subnet2"
  omit_external_ip = true
  use_internal_ip  = true
  network_project_id       = "ggn-nmfs-pamdata-prod-1"
  image_description        = "newly patched image from latest pam windows workstation family"
  enable_secure_boot       = false
  enable_integrity_monitoring = false
  enable_vtpm              = false
  disk_size                = 250
  image_family             = "pam-windows-workstation"
  image_name               = "pww-latest-patched-{{timestamp}}"
}

build {
  sources = ["sources.googlecompute.update-pam-ww"]

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

  # use manual shutdown to logoff the admin user, lack of which resulted in end
  # user account not able to shut down the instance within windows upon provisioning.
  provisioner "powershell" {
    inline = [
      "shutdown /s /f /t 0"
    ]
  }
}
