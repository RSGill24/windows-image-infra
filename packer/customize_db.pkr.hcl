packer {
  required_version = ">= 1.8.0"

  required_plugins {
    googlecompute = {
      version = ">= 1.1.6"
      source  = "github.com/hashicorp/googlecompute"
    }
    ansible = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "packer_user_password" {
  type      = string
  default   = env("PACKER_PW")
  sensitive = true
}

variable "project_id" {
  type = string
}

variable "source_image_project_id" {
  type        = string
  description = "Project ID containing the source image"
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

variable "database_type" {
  type    = string
  default = "none"
}

variable "installation_source_dir" {
  type = string
}

variable "installation_target_dir" {
  type = string
}

variable "installation_entry_script" {
  type = string
}

source "googlecompute" "customize_with_db" {
  project_id              = var.project_id
  use_iap                 = true
  use_internal_ip         = true
  omit_external_ip        = true
  source_image_project_id = [var.source_image_project_id]
  source_image_family     = var.source_image_family

  communicator   = "winrm"
  winrm_username = "packer_user"
  winrm_password = var.packer_user_password
  winrm_use_ssl  = true
  winrm_insecure = true
  winrm_port     = 5986
  winrm_timeout  = "90m"

  service_account_email       = var.service_account_email
  zone                        = var.zone
  enable_secure_boot          = true
  enable_integrity_monitoring = true
  enable_vtpm                 = true

  disk_size  = 250
  network    = "app-network"
  subnetwork = "app-subnet1"
  tags       = ["winrm"]

  image_family = var.image_family
  image_name   = "pww-disa-hardened-${var.database_type}-db-{{timestamp}}"
  machine_type = var.machine_type

  metadata = {
    windows-startup-script-ps1 = <<EOF
net user packer_user "${var.packer_user_password}" /add /y
net localgroup Administrators packer_user /add

winrm quickconfig -q
Enable-PSRemoting -Force

$cert = New-SelfSignedCertificate -DnsName "packer" -CertStoreLocation Cert:\LocalMachine\My
$thumb = $cert.Thumbprint

Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains "Transport=HTTPS" } | Remove-Item -Recurse -Force
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $thumb -Force

Set-Item -Path WSMan:\localhost\Service\Auth\Basic       -Value $true
Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate   -Value $true
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false
Set-Item -Path WSMan:\localhost\MaxTimeoutms             -Value 1800000

netsh advfirewall firewall add rule name="WinRM-HTTPS" dir=in action=allow protocol=TCP localport=5986

Write-EventLog -LogName Application -Source "GCEMetadataScripts" -EventId 1 -Message "WinRM setup complete" -EntryType Information
EOF
  }
}

build {
  sources = ["sources.googlecompute.customize_with_db"]

  # Step 1: Confirm connection and prep environment
  provisioner "powershell" {
    inline = [
      "Write-Host 'Connected as:' $env:USERNAME",
      "try { Add-LocalGroupMember -Group 'Administrators' -Member 'packer_user' -ErrorAction Stop } catch {}",
      "Set-Service -Name seclogon -StartupType Manual -ErrorAction SilentlyContinue",
      "Start-Service -Name seclogon -ErrorAction SilentlyContinue",
      "New-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System' -Name 'LocalAccountTokenFilterPolicy' -Value 1 -PropertyType DWord -Force | Out-Null",
      "Write-Host 'Environment ready for Ansible-based database installation.'"
    ]
  }

  # Step 2: Run database installation via Ansible
  provisioner "ansible" {
    playbook_file = "${var.installation_source_dir}/../ansible-playbook/database_installation.yml"
    user          = "packer_user"
    use_proxy     = false
    extra_arguments = [
      "-e", "ansible_host={{ build `Host` }}",
      "-e", "ansible_winrm_server_cert_validation=ignore",
      "-e", "ansible_winrm_scheme=https",
      "-e", "ansible_winrm_port=5986",
      "-e", "ansible_winrm_transport=basic",
      "-e", "ansible_user=packer_user",
      "-e", "ansible_password=${var.packer_user_password}",
      "-e", "database_type=${var.database_type}"
    ]
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "DATABASE_TYPE=${var.database_type}",
      "PACKER_PW=${var.packer_user_password}"
    ]
  }
}