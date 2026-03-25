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

  communicator   = "winrm"
  winrm_username = "packer_user"
  winrm_password = var.packer_user_password
  winrm_use_ssl  = true
  winrm_insecure = true
  winrm_port     = 5986
  # FIX 1: Increased from 40m to 90m.
  # STIG hardening (PowerSTIG install + DSC MOF compilation + DSC apply
  # + targeted remediation) routinely takes 45-70 minutes on a fresh image.
  # A 40m timeout causes Packer to disconnect mid-hardening and mark the
  # build as failed even though the scripts are still running.
  winrm_timeout = "90m"

  service_account_email = var.service_account_email
  zone                  = var.zone

  # FIX 2: enable_secure_boot must be true for V-254284 STIG compliance.
  # This enables Shielded VM Secure Boot at the GCP image level — it cannot
  # be set from inside the guest OS, so it MUST be set here in Packer.
  # If your GCP project does not allow Shielded VMs, set to false and
  # document V-254284 as an ISSO-approved exception.
  enable_secure_boot = true

  # Integrity monitoring and vTPM should also be enabled for Shielded VM.
  # Both are required for a fully Shielded VM configuration.
  enable_integrity_monitoring = true
  enable_vtpm                 = true

  disk_size  = 250
  network    = "app-network"
  subnetwork = "app-subnet1"
  tags       = ["winrm"]

  image_family = var.image_family
  image_name   = "pww-disa-${var.source_image}-hardened-patched-{{timestamp}}"
  machine_type = var.machine_type

  metadata = {
    windows-startup-script-ps1 = <<EOF
# Step 1: Create packer_user FIRST with the correct password
net user packer_user "${var.packer_user_password}" /add /y
net localgroup Administrators packer_user /add

# Step 2: Configure WinRM
winrm quickconfig -q
Enable-PSRemoting -Force

# Step 3: Create self-signed cert and configure HTTPS listener
$cert = New-SelfSignedCertificate -DnsName "packer" -CertStoreLocation Cert:\LocalMachine\My
$thumb = $cert.Thumbprint

# Remove existing HTTPS listener if any, then create new one
Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains "Transport=HTTPS" } | Remove-Item -Recurse -Force
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $thumb -Force

# Step 4: Auth settings
Set-Item -Path WSMan:\localhost\Service\Auth\Basic      -Value $true
Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate  -Value $true
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false
Set-Item -Path WSMan:\localhost\MaxTimeoutms            -Value 1800000

# Step 5: Firewall rule — open port LAST so Packer only connects when ready
netsh advfirewall firewall add rule name="WinRM-HTTPS" dir=in action=allow protocol=TCP localport=5986

Write-EventLog -LogName Application -Source "GCEMetadataScripts" -EventId 1 -Message "WinRM setup complete" -EntryType Information
EOF
  }
}

build {
  sources = ["sources.googlecompute.update_pam_ww"]

  # Step 1: Confirm connection and ensure packer_user is in Administrators.
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

  # Step 3: Upload hardening scripts to the instance — one file at a time.
  #
  # FIX 3: Replaced the single directory "file" provisioner with individual
  # per-file provisioners. The original approach used:
  #   source      = "${var.hardening_source_dir}/"
  #   destination = var.hardening_target_dir
  # This causes Packer's WinRM file upload to silently TRUNCATE large scripts
  # (> ~100 KB) because WinRM splits the file into chunks and the directory
  # upload mode does not wait for each chunk to flush before moving on.
  # The result is a syntactically broken script (MissingEndCurlyBrace) even
  # though the source file on disk is perfectly valid.
  #
  # Fix: upload each script individually with its full destination path.
  # This forces WinRM to complete each file transfer before starting the next.
  #
  # If you add new scripts to the hardening directory, add them here too.

  provisioner "file" {
    source      = "${var.hardening_source_dir}/run_all.ps1"
    destination = "${var.hardening_target_dir}/run_all.ps1"
  }

  provisioner "file" {
    source      = "${var.hardening_source_dir}/install_PowerSTIG.ps1"
    destination = "${var.hardening_target_dir}/install_PowerSTIG.ps1"
  }

  provisioner "file" {
    source      = "${var.hardening_source_dir}/install_dsc_deps.ps1"
    destination = "${var.hardening_target_dir}/install_dsc_deps.ps1"
  }

  provisioner "file" {
    source      = "${var.hardening_source_dir}/install_dod_certs.ps1"
    destination = "${var.hardening_target_dir}/install_dod_certs.ps1"
  }

  provisioner "file" {
    source      = "${var.hardening_source_dir}/create_mof.ps1"
    destination = "${var.hardening_target_dir}/create_mof.ps1"
  }

  provisioner "file" {
    source      = "${var.hardening_source_dir}/apply_mof.ps1"
    destination = "${var.hardening_target_dir}/apply_mof.ps1"
  }

  provisioner "file" {
    source      = "${var.hardening_source_dir}/account_policy.ps1"
    destination = "${var.hardening_target_dir}/account_policy.ps1"
  }

  provisioner "file" {
    source      = "${var.hardening_source_dir}/registry_stig.ps1"
    destination = "${var.hardening_target_dir}/registry_stig.ps1"
  }

  provisioner "file" {
    source      = "${var.hardening_source_dir}/services_stig.ps1"
    destination = "${var.hardening_target_dir}/services_stig.ps1"
  }

  provisioner "file" {
    source      = "${var.hardening_source_dir}/stig_remediation_fixes.ps1"
    destination = "${var.hardening_target_dir}/stig_remediation_fixes.ps1"
  }

  provisioner "file" {
    source      = "${var.hardening_source_dir}/repair_winrm_for_packer.ps1"
    destination = "${var.hardening_target_dir}/repair_winrm_for_packer.ps1"
  }

  # Upload the org settings XML alongside the scripts.
  # The filename must match what install_dsc_deps.ps1 generates
  # (WindowsServer-2022-MS-<version>.org.pamdata.xml).
  # If the version changes (e.g. 2.7 -> 3.0), update this filename.
  provisioner "file" {
    source      = "${var.hardening_source_dir}/WindowsServer-2022-MS-2.7.org.pamdata.xml"
    destination = "${var.hardening_target_dir}/WindowsServer-2022-MS-2.7.org.pamdata.xml"
  }

  # Step 4: Verify all uploaded scripts are intact before running hardening.
  # FIX 4: This step catches truncation before it causes silent failures
  # mid-hardening (e.g. MissingEndCurlyBrace in install_dod_certs.ps1).
  provisioner "powershell" {
    elevated_user     = "packer_user"
    elevated_password = var.packer_user_password
    inline = [
      "Write-Host '--- Pre-hardening script integrity check ---'",
      "$checks = @(",
      "  @{ File='install_dod_certs.ps1';      MinLines=200 },",
      "  @{ File='stig_remediation_fixes.ps1'; MinLines=100 },",
      "  @{ File='install_dsc_deps.ps1';       MinLines=50  },",
      "  @{ File='create_mof.ps1';             MinLines=50  }",
      ")",
      "$failed = $false",
      "foreach ($c in $checks) {",
      "  $path = '${var.hardening_target_dir}/' + $c.File",
      "  if (Test-Path $path) {",
      "    $lines = (Get-Content $path).Count",
      "    $hash  = (Get-FileHash $path -Algorithm SHA256).Hash.Substring(0,16)",
      "    Write-Host \"  $($c.File): $lines lines | SHA256: $hash...\"",
      "    if ($lines -lt $c.MinLines) {",
      "      Write-Error \"TRUNCATED: $($c.File) has only $lines lines (expected >= $($c.MinLines))\"",
      "      $failed = $true",
      "    }",
      "  } else {",
      "    Write-Error \"MISSING: $path\"",
      "    $failed = $true",
      "  }",
      "}",
      "if ($failed) { exit 1 }",
      "Write-Host 'All scripts verified OK.'"
    ]
  }

  # Step 5: Run the STIG hardening pipeline.
  # FIX 5: Increased execution_timeout to match winrm_timeout.
  # Without this, Packer kills the PowerShell process after the default
  # timeout even though the WinRM session itself is still alive.
  provisioner "powershell" {
    inline = [
      "Set-Location '${var.hardening_target_dir}'",
      "& '${var.hardening_target_dir}/${var.hardening_entry_script}'"
    ]
    elevated_user     = "packer_user"
    elevated_password = var.packer_user_password
    execution_timeout = "85m"
  }
}
