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
  image_name   = "pww-disa-${var.source_image}-hardened-patched-{{timestamp}}"
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

  # Step 3: Upload each hardening script individually with its full destination
  # path. Do NOT use directory-mode upload (trailing slash on source) — it
  # silently truncates large scripts over WinRM, causing parse errors like
  # MissingEndCurlyBrace mid-build.
  #
  # NOTE: WindowsServer-2022-MS-2.7.org.pamdata.xml is NOT uploaded here.
  # It does not exist at build time — install_dsc_deps.ps1 generates it
  # dynamically on the VM from the PowerSTIG module's bundled default XML
  # and then applies the PAM overrides defined in that script.

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

  # Step 4: Verify uploaded scripts are intact before running hardening.
  # Catches WinRM truncation early with a clear error rather than a cryptic
  # PowerShell parse failure mid-build.
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
      "  $path = Join-Path '${var.hardening_target_dir}' $c.File",
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
  # FIX: 'execution_timeout' is not a valid argument for the powershell
  # provisioner — the correct argument is 'timeout' (a duration string).
  # Set to 85m, just under the 90m winrm_timeout, so Packer reports a
  # clean timeout error rather than a confusing WinRM disconnect.
  provisioner "powershell" {
    inline = [
      "Set-Location '${var.hardening_target_dir}'",
      "& '${var.hardening_target_dir}/${var.hardening_entry_script}'"
    ]
    elevated_user     = "packer_user"
    elevated_password = var.packer_user_password
    timeout           = "85m"
  }
}
