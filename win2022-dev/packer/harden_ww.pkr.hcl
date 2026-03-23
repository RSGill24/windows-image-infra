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
  use_internal_ip         = true
  omit_external_ip        = true
  source_image_project_id = [var.source_image_project_id]
  source_image_family     = var.source_image_family

  communicator            = "winrm"
  winrm_username          = "packer_user"
  winrm_password          = var.packer_user_password
  winrm_use_ssl           = true
  winrm_insecure          = true
  winrm_port              = 5986
  winrm_timeout           = "40m"
  pause_before_connecting = "3m"   # FIX: Give WinRM time to fully initialize before Packer connects

  service_account_email       = var.service_account_email
  zone                        = var.zone
  enable_secure_boot          = false
  enable_integrity_monitoring = false
  enable_vtpm                 = false
  disk_size                   = 250
  network                     = "default"
  subnetwork                  = "default"
  tags                        = ["winrm"]

  image_family = var.image_family
  image_name   = "pww-disa-${var.source_image}-hardened-patched-{{timestamp}}"
  machine_type = var.machine_type

  metadata = {
    windows-startup-script-ps1 = <<EOF
# -----------------------------------------------------------------------
# Step 1: Create packer_user using SecureString to handle special characters
#         in the password (e.g. !, &, ^) that break plain "net user".
# -----------------------------------------------------------------------
$Password = ConvertTo-SecureString "${var.packer_user_password}" -AsPlainText -Force
New-LocalUser -Name "packer_user" -Password $Password -PasswordNeverExpires -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group "Administrators" -Member "packer_user" -ErrorAction SilentlyContinue

# -----------------------------------------------------------------------
# Step 2: Enable PSRemoting only (already includes winrm quickconfig
#         internally — running both can reset listener state).
# -----------------------------------------------------------------------
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# -----------------------------------------------------------------------
# Step 3: Create a self-signed certificate and configure HTTPS listener.
# -----------------------------------------------------------------------
$cert = New-SelfSignedCertificate -DnsName "packer" -CertStoreLocation Cert:\LocalMachine\My
$thumb = $cert.Thumbprint

# Remove any existing HTTPS listener to avoid conflicts
Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains "Transport=HTTPS" } | Remove-Item -Recurse -Force

# Create fresh HTTPS listener with the new cert
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $thumb -Force

# -----------------------------------------------------------------------
# Step 4: Configure WinRM auth and service settings.
# -----------------------------------------------------------------------
Set-Item -Path WSMan:\localhost\Service\Auth\Basic    -Value $true
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false
Set-Item -Path WSMan:\localhost\MaxTimeoutms          -Value 1800000

# -----------------------------------------------------------------------
# Step 5: Restart WinRM and wait for the cert to fully bind.
#         Without this delay, the firewall opens before WinRM is ready
#         causing the "401 - invalid content type" error.
# -----------------------------------------------------------------------
Restart-Service WinRM
Start-Sleep -Seconds 15

# -----------------------------------------------------------------------
# Step 6: Open the firewall port LAST — only after WinRM is fully ready.
# -----------------------------------------------------------------------
netsh advfirewall firewall add rule name="WinRM-HTTPS" dir=in action=allow protocol=TCP localport=5986

Write-EventLog -LogName Application -Source "GCEMetadataScripts" -EventId 1 -Message "WinRM HTTPS setup complete on port 5986" -EntryType Information
EOF
  }
}

build {
  sources = ["sources.googlecompute.update_pam_ww"]

  # Step 1: Confirm connection and verify packer_user is in Administrators.
  provisioner "powershell" {
    inline = [
      "Write-Host 'Connected as:' $env:USERNAME",
      "try { Add-LocalGroupMember -Group 'Administrators' -Member 'packer_user' -ErrorAction Stop } catch {}",
      "Write-Host 'Setup verified.'"
    ]
  }

  # Step 2: Install PSWindowsUpdate and apply Windows Updates.
  provisioner "powershell" {
    inline = [
      "Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force",
      "Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck",
      "Get-WindowsUpdate -Install -AcceptAll -AutoReboot:$false"
    ]
    elevated_user     = "packer_user"
    elevated_password = var.packer_user_password
  }

  # Step 3: Copy hardening scripts to the instance.
  # Trailing slash on source copies the *contents* of the folder,
  # so scripts land directly in hardening_target_dir (not a sub-folder).
  provisioner "file" {
    source      = "${var.hardening_source_dir}/"
    destination = var.hardening_target_dir
  }

  # Step 4: Run the hardening entry script.
  # Set-Location ensures the working directory is correct so that
  # any relative-path calls inside the entry script resolve properly.
  provisioner "powershell" {
    inline = [
      "Set-Location '${var.hardening_target_dir}'",
      "& '${var.hardening_target_dir}${var.hardening_entry_script}'"
    ]
    elevated_user     = "packer_user"
    elevated_password = var.packer_user_password
  }
}
