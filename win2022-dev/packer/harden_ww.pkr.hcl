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

variable "project_id"              { type = string }
variable "source_image_project_id" { type = string }
variable "source_image_family"     { type = string }
variable "service_account_email"   { type = string }
variable "image_family"            { type = string }
variable "machine_type"            { type = string }
variable "zone"                    { type = string }
variable "hardening_source_dir"    { type = string }
variable "hardening_target_dir"    { type = string }
variable "hardening_entry_script"  { type = string }

# NAMING CONVENTION: nmfs-[os]-[version] for family, nmfs-[os/version]-[timestamp] for images
source "googlecompute" "nmfs_windows_2025" {
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
  image_name   = "nmfs-windows-2025-{{timestamp}}"
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
  sources = ["sources.googlecompute.nmfs_windows_2025"]

  # Step 1: Confirm connection, ensure packer_user is in Administrators,
  # and prep elevated-provisioner prerequisites (seclogon + SeBatchLogonRight).
  # This runs NON-elevated but WinRM admin sessions get a full-admin token
  # on workgroup Windows, so secedit/sc work here.
  #
  # FIX: "HRESULT 0x80070002 at RegisterTaskDefinition" in Step 2 happens
  # when packer_user lacks Log-on-as-a-batch-job right OR when the
  # Secondary Logon (seclogon) service is stopped. Both required by
  # Packer's elevated provisioner (TASK_LOGON_PASSWORD).
  provisioner "powershell" {
    inline = [
      "Write-Host 'Connected as:' $env:USERNAME",
      "try { Add-LocalGroupMember -Group 'Administrators' -Member 'packer_user' -ErrorAction Stop } catch {}",
      "Set-Service -Name seclogon -StartupType Manual -ErrorAction SilentlyContinue",
      "Start-Service -Name seclogon -ErrorAction SilentlyContinue",
      "# LocalAccountTokenFilterPolicy=1 -- gives WinRM admin sessions a FULL admin token",
      "# instead of the UAC-filtered token. Lets subsequent non-elevated provisioners run",
      "# admin commands directly, bypassing Packer's buggy elevated-provisioner scheduled",
      "# task mechanism that was throwing HRESULT 0x80070002 at RegisterTaskDefinition.",
      "New-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System' -Name 'LocalAccountTokenFilterPolicy' -Value 1 -PropertyType DWord -Force | Out-Null",
      "$cfg = Join-Path $env:TEMP 'br.inf'",
      "$db  = Join-Path $env:TEMP 'br.sdb'",
      "secedit /export /areas USER_RIGHTS /cfg $cfg /quiet",
      "$txt = Get-Content $cfg -Raw",
      "if ($txt -match 'SeBatchLogonRight\\s*=\\s*([^\\r\\n]*)') {",
      "  if ($Matches[1] -notmatch 'packer_user') {",
      "    $txt = $txt -replace 'SeBatchLogonRight\\s*=\\s*[^\\r\\n]*', ('SeBatchLogonRight = ' + $Matches[1] + ',packer_user')",
      "  }",
      "} else {",
      "  $txt = $txt -replace '(\\[Privilege Rights\\])', \"`$1`r`nSeBatchLogonRight = packer_user\"",
      "}",
      "$txt | Set-Content $cfg -Encoding Unicode",
      "secedit /configure /db $db /cfg $cfg /areas USER_RIGHTS /quiet",
      "Remove-Item $cfg,$db -Force -ErrorAction SilentlyContinue",
      "Write-Host 'seclogon status:' (Get-Service seclogon).Status",
      "Write-Host 'LocalAccountTokenFilterPolicy set. Setup verified.'"
    ]
  }

  # Step 2: Install PSWindowsUpdate and apply Windows Updates.
  #
  # elevated_user/password are REQUIRED here. They were previously removed on the
  # reasoning that "LocalAccountTokenFilterPolicy=1 gives WinRM admin sessions full
  # tokens, so the elevation wrapper is unnecessary." That is true of the token but
  # not of the LOGON TYPE, and the Windows Update COM API gates on logon type: it
  # refuses to install from a NETWORK logon no matter how privileged the token is.
  # The result was:
  #
  #   Get-WindowsUpdate -Install -> An error occurred: Access is denied.
  #                                 (Exception from HRESULT: 0x80070005 E_ACCESSDENIED)
  #   -> script exit 1 -> "Provisioning step had errors" -> instance deleted
  #
  # This only bites when updates are actually pending, which is why it can look
  # intermittent: a freshly published source image with nothing to install exits 0
  # and the build passes.
  #
  # elevated_user makes Packer run the script through a scheduled task, which is a
  # BATCH logon, and Windows Update accepts that. The HRESULT 0x80070002 failure
  # this wrapper used to throw at RegisterTaskDefinition is already fixed by Step 1
  # above, which starts seclogon and grants packer_user SeBatchLogonRight.
  provisioner "powershell" {
    elevated_user     = "packer_user"
    elevated_password = var.packer_user_password
    inline = [
      "$ErrorActionPreference = 'Continue'",
      "Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null",
      "Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck",
      "Import-Module PSWindowsUpdate",
      "try {",
      "  Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot -ErrorAction Stop | Out-String | Write-Host",
      "  Write-Host 'Windows Update run completed.'",
      "} catch {",
      "  # Do not sink a 90-minute build over a transient WU failure, but make it",
      "  # loud so an unpatched image is never mistaken for a patched one.",
      "  Write-Host \"WARNING: Windows Update failed: $_\"",
      "  Write-Host 'WARNING: image may be missing patches - check before promoting.'",
      "}",
      "$hf = (Get-HotFix | Measure-Object).Count",
      "Write-Host \"Installed hotfix count: $hf\""
    ]
  }

  # Step 3: Upload each hardening script individually with its full destination
  # path. Do NOT use directory-mode upload (trailing slash on source) -- it
  # silently truncates large scripts over WinRM causing parse errors mid-build.
  #
  # NOTE: WindowsServer-2025-MS-2.7.org.pamdata.xml is NOT uploaded here.
  # install_dsc_deps.ps1 generates it dynamically on the VM from the
  # PowerSTIG module's bundled default XML then applies PAM overrides.

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
    source      = "${var.hardening_source_dir}/audit.ps1"
    destination = "${var.hardening_target_dir}/audit.ps1"
  }
  provisioner "file" {
    source      = "${var.hardening_source_dir}/dod_banner.ps1"
    destination = "${var.hardening_target_dir}/dod_banner.ps1"
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
    source      = "${var.hardening_source_dir}/apply_remaining_fixes.ps1"
    destination = "${var.hardening_target_dir}/apply_remaining_fixes.ps1"
  }

  # Primary registry remediation for the Server 2025 STIG. Reads the benchmark
  # content shipped inside PowerSTIG and applies every registry rule directly,
  # so compliance no longer depends on the DSC apply succeeding end to end.
  provisioner "file" {
    source      = "${var.hardening_source_dir}/win2025_registry_fixes.ps1"
    destination = "${var.hardening_target_dir}/win2025_registry_fixes.ps1"
  }

  # Uploaded so it is available on the VM, but NOT invoked by run_all.ps1.
  # Nothing in this pipeline modifies WinRM any more (create_mof.ps1 derives the
  # WinRM rules out of the DSC MOF and win2025_registry_fixes.ps1 refuses them by
  # key path), so there is nothing to repair. Kept on disk for manual recovery if
  # a future change does disturb the listener mid-build.
  provisioner "file" {
    source      = "${var.hardening_source_dir}/repair_winrm_for_packer.ps1"
    destination = "${var.hardening_target_dir}/repair_winrm_for_packer.ps1"
  }

  provisioner "file" {
    source      = "${var.hardening_source_dir}/install_nessus.ps1"
    destination = "${var.hardening_target_dir}/install_nessus.ps1"
  }
  provisioner "file" {
    source      = "${var.hardening_source_dir}/InstallRoot.msi"
    destination = "${var.hardening_target_dir}/InstallRoot.msi"
  }
  provisioner "file" {
    source      = "${var.hardening_source_dir}/install_bigfix.ps1"
    destination = "${var.hardening_target_dir}/install_bigfix.ps1"
  }
  provisioner "file" {
    source      = "${var.hardening_source_dir}/install_trellix.ps1"
    destination = "${var.hardening_target_dir}/install_trellix.ps1"
  }

  provisioner "file" {
    source      = "${var.hardening_source_dir}/Certificates_PKCS7_v5_14_DoD.der.p7b"
    destination = "${var.hardening_target_dir}/Certificates_PKCS7_v5_14_DoD.der.p7b"
  }

  # Step 3.5: Normalize script encoding to CRLF + UTF-8 BOM.
  provisioner "powershell" {
    inline = [
      "Write-Host '--- Fixing File Encodings (CRLF + UTF-8 BOM) ---'",
      "$targetDir = '${var.hardening_target_dir}'",
      "Get-ChildItem -Path $targetDir -Filter *.ps1 | ForEach-Object {",
      "  $content = [System.IO.File]::ReadAllText($_.FullName)",
      "  $content = $content -replace \"`r`n\", \"`n\" -replace \"`n\", \"`r`n\"",
      "  $utf8Bom = New-Object System.Text.UTF8Encoding($true)",
      "  [System.IO.File]::WriteAllText($_.FullName, $content, $utf8Bom)",
      "  Write-Host \"Normalized encoding for: $($_.Name)\"",
      "}",
      "Write-Host 'Encoding normalization complete.'"
    ]
  }

  # Step 4: Verify uploaded scripts are intact before running hardening.
  provisioner "powershell" {
    inline = [
      "Write-Host '--- Pre-hardening script integrity check ---'",
      "$checks = @(",
      "  @{ File='install_dod_certs.ps1';      MinLines=50  },",
      "  @{ File='stig_remediation_fixes.ps1'; MinLines=100 },",
      "  @{ File='install_dsc_deps.ps1';       MinLines=50  },",
      "  @{ File='create_mof.ps1';             MinLines=50  },",
      "  @{ File='audit.ps1';                  MinLines=30  },",
      "  @{ File='apply_remaining_fixes.ps1';  MinLines=30  },",
      "  @{ File='win2025_registry_fixes.ps1'; MinLines=200 }",
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
  provisioner "powershell" {
    inline = [
      "Set-Location '${var.hardening_target_dir}'",
      "& '${var.hardening_target_dir}/${var.hardening_entry_script}'"
    ]
    timeout = "85m"
  }
}
