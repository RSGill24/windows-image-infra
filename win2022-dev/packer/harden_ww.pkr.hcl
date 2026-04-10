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

  # -----------------------------------------------------------------------
  # Step 1: Confirm connection and ensure packer_user is in Administrators.
  # -----------------------------------------------------------------------
  provisioner "powershell" {
    inline = [
      "Write-Host 'Connected as:' $env:USERNAME",
      "try { Add-LocalGroupMember -Group 'Administrators' -Member 'packer_user' -ErrorAction Stop } catch {}",
      "Write-Host 'Setup verified.'"
    ]
  }

  # -----------------------------------------------------------------------
  # Step 2: Install PSWindowsUpdate and apply Windows Updates.
  # -----------------------------------------------------------------------
  provisioner "powershell" {
    inline = [
      "Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force",
      "Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck",
      "Get-WindowsUpdate -Install -AcceptAll -AutoReboot:$false"
    ]
    elevated_user     = "packer_user"
    elevated_password = var.packer_user_password
  }

  # -----------------------------------------------------------------------
  # Step 3: Upload each hardening script individually.
  # Do NOT use directory-mode upload (trailing slash on source) -- it
  # silently truncates large scripts over WinRM causing parse errors.
  # -----------------------------------------------------------------------
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
    source      = "${var.hardening_source_dir}/repair_winrm_for_packer.ps1"
    destination = "${var.hardening_target_dir}/repair_winrm_for_packer.ps1"
  }

  provisioner "file" {
    source      = "${var.hardening_source_dir}/Certificates_PKCS7_v5_14_DoD.der.p7b"
    destination = "${var.hardening_target_dir}/Certificates_PKCS7_v5_14_DoD.der.p7b"
  }

  # -----------------------------------------------------------------------
  # Step 3.5: Normalize script encoding to CRLF + UTF-8 BOM.
  # Prevents PowerShell parse errors caused by encoding mismatches
  # introduced during WinRM file transfer.
  # -----------------------------------------------------------------------
  provisioner "powershell" {
    elevated_user     = "packer_user"
    elevated_password = var.packer_user_password
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

  # -----------------------------------------------------------------------
  # Step 4: Verify uploaded scripts are intact before running hardening.
  # -----------------------------------------------------------------------
  provisioner "powershell" {
    elevated_user     = "packer_user"
    elevated_password = var.packer_user_password
    inline = [
      "Write-Host '--- Pre-hardening script integrity check ---'",
      "$checks = @(",
      "  @{ File='install_dod_certs.ps1';      MinLines=50  },",
      "  @{ File='stig_remediation_fixes.ps1'; MinLines=100 },",
      "  @{ File='install_dsc_deps.ps1';       MinLines=50  },",
      "  @{ File='create_mof.ps1';             MinLines=50  },",
      "  @{ File='audit.ps1';                  MinLines=30  },",
      "  @{ File='apply_remaining_fixes.ps1';  MinLines=30  }",
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

  # -----------------------------------------------------------------------
  # Step 5a: DSC pipeline ONLY (install + create_mof + apply_mof)
  #
  # WHY SEPARATE: apply_mof.ps1 ke andar DSC UserRightsAssignment secedit
  # write karta hai jo WinRM tod deta hai. apply_mof.ps1 khud WinRM restore
  # aur verify karta hai, lekin Packer ke cleanup script upload ka attempt
  # WinRM ready hone se PEHLE hota tha — 401 error ka root cause.
  #
  # Is provisioner ke end mein apply_mof.ps1 WinRM verified ready hai.
  # Packer ka cleanup tab try karta hai — WinRM already stable hai.
  # Step 5b tab chalti hai — fresh connection, guaranteed working WinRM.
  # -----------------------------------------------------------------------
  provisioner "powershell" {
    elevated_user     = "packer_user"
    elevated_password = var.packer_user_password
    timeout           = "75m"
    inline = [
      "Set-Location '${var.hardening_target_dir}'",
      "Write-Host '=== Step 5a: DSC pipeline start ==='",

      "Write-Host '--- install_PowerSTIG ---'",
      "& '${var.hardening_target_dir}/install_PowerSTIG.ps1'",
      "if ($LASTEXITCODE -ne 0) { Write-Error 'install_PowerSTIG failed'; exit $LASTEXITCODE }",

      "Write-Host '--- install_dsc_deps ---'",
      "& '${var.hardening_target_dir}/install_dsc_deps.ps1'",
      "if ($LASTEXITCODE -ne 0) { Write-Error 'install_dsc_deps failed'; exit $LASTEXITCODE }",

      "Write-Host '--- create_mof ---'",
      "& '${var.hardening_target_dir}/create_mof.ps1'",
      "if ($LASTEXITCODE -ne 0) { Write-Error 'create_mof failed'; exit $LASTEXITCODE }",

      "Write-Host '--- apply_mof (WinRM auto-restored + verified inside) ---'",
      "& '${var.hardening_target_dir}/apply_mof.ps1'",
      "if ($LASTEXITCODE -ne 0) { Write-Error 'apply_mof failed'; exit $LASTEXITCODE }",

      "Write-Host '=== Step 5a complete — WinRM ready for Step 5b ==='"
    ]
  }

  # -----------------------------------------------------------------------
  # Step 5b: Post-DSC scripts (agents, certs, policy, fixes, banner)
  #
  # WHY SEPARATE: Yeh provisioner tab start hota hai jab Packer Step 5a se
  # fresh WinRM connection banata hai. apply_mof.ps1 ne WinRM verify loop
  # chala ke confirm kiya hai ki connection accept ho raha hai.
  # Isliye yahan sab scripts safely chalti hain.
  # -----------------------------------------------------------------------
  provisioner "powershell" {
    elevated_user     = "packer_user"
    elevated_password = var.packer_user_password
    timeout           = "30m"
    inline = [
      "Set-Location '${var.hardening_target_dir}'",
      "Write-Host '=== Step 5b: Post-DSC pipeline start ==='",

      "Write-Host '--- install_bigfix ---'",
      "& '${var.hardening_target_dir}/install_bigfix.ps1'",

      "Write-Host '--- install_nessus ---'",
      "& '${var.hardening_target_dir}/install_nessus.ps1'",

      "Write-Host '--- install_trellix ---'",
      "& '${var.hardening_target_dir}/install_trellix.ps1'",

      "Write-Host '--- install_dod_certs ---'",
      "& '${var.hardening_target_dir}/install_dod_certs.ps1'",

      "Write-Host '--- registry_stig ---'",
      "& '${var.hardening_target_dir}/registry_stig.ps1'",

      "Write-Host '--- services_stig ---'",
      "& '${var.hardening_target_dir}/services_stig.ps1'",

      "Write-Host '--- account_policy ---'",
      "& '${var.hardening_target_dir}/account_policy.ps1'",
      "if ($LASTEXITCODE -ne 0) { Write-Error 'account_policy failed'; exit $LASTEXITCODE }",

      "Write-Host '--- audit ---'",
      "& '${var.hardening_target_dir}/audit.ps1'",

      "Write-Host '--- apply_remaining_fixes ---'",
      "& '${var.hardening_target_dir}/apply_remaining_fixes.ps1'",

      "Write-Host '--- stig_remediation_fixes ---'",
      "& '${var.hardening_target_dir}/stig_remediation_fixes.ps1'",

      "Write-Host '--- dod_banner ---'",
      "& '${var.hardening_target_dir}/dod_banner.ps1'",

      "Write-Host '--- repair_winrm_for_packer (LAST) ---'",
      "& '${var.hardening_target_dir}/repair_winrm_for_packer.ps1'",

      "Write-Host '=== Step 5b complete ==='"
    ]
  }
}
