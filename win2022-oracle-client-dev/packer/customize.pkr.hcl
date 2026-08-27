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

# ── Auth ──────────────────────────────────────────────────────────────────────
variable "packer_user_password" {
  type      = string
  default   = env("PACKER_PW")
  sensitive = true
}

# ── GCP / image settings ──────────────────────────────────────────────────────
variable "project_id"              { type = string }
variable "source_image_project_id" { type = string }
variable "source_image_family"     { type = string }
variable "service_account_email"   { type = string }
variable "image_family"            { type = string }
variable "image_name" {
  type    = string
  default = ""
}
variable "machine_type"            { type = string }
variable "zone"                    { type = string }
variable "installation_source_dir" { type = string }
variable "installation_target_dir" { type = string }
variable "vm_network" {
  type    = string
  default = "app-network"
}

variable "vm_subnet" {
  type    = string
  default = "app-subnet1"
}

# ── Component-selection flags ─────────────────────────────────────────────────
# Passed from the entrypoint/Cloud Run env vars → packer -var → ansible -e

variable "install_oracle" {
  type    = string
  default = "false"
  description = "Install Oracle Instant Client + SQL*Plus"
}

variable "install_rstudio" {
  type    = string
  default = "false"
  description = "Install R + RStudio Desktop (OSS) via Chocolatey"
}

variable "install_conda" {
  type    = string
  default = "false"
  description = "Install Miniconda3 (conda + Python) via Chocolatey"
}

variable "install_chrome" {
  type    = string
  default = "false"
  description = "Install Google Chrome via Chocolatey"
}

variable "install_git" {
  type    = string
  default = "false"
  description = "Install Git + GitHub Desktop via Chocolatey"
}

variable "install_python" {
  type    = string
  default = "false"
  description = "Install standalone Python via Chocolatey"
}

variable "install_jupyterlab" {
  type    = string
  default = "false"
  description = "Install JupyterLab via pip (requires Python)"
}

variable "install_powershell_core" {
  type    = string
  default = "false"
  description = "Install PowerShell 7+ via Chocolatey"
}

variable "install_pycharm" {
  type    = string
  default = "false"
  description = "Install PyCharm Community Edition via Chocolatey"
}

variable "install_visual_studio" {
  type    = string
  default = "false"
  description = "Install Visual Studio 2022 Community via Chocolatey"
}

variable "install_paraview" {
  type    = string
  default = "false"
  description = "Install ParaView via Chocolatey"
}

variable "install_echoview" {
  type    = string
  default = "false"
  description = "Install Echoview v16+ (binary from GCS)"
}

variable "install_matlab" {
  type    = string
  default = "false"
  description = "Install MATLAB (binary from GCS)"
}

variable "install_rstudio_pro" {
  type    = string
  default = "false"
  description = "Install RStudio Pro / Posit Workbench (binary from GCS)"
}

variable "install_positron" {
  type    = string
  default = "false"
  description = "Install Positron IDE (binary from GCS)"
}

variable "install_anaconda" {
  type    = string
  default = "false"
  description = "Install full Anaconda distribution via Chocolatey"
}

variable "install_gpu_drivers" {
  type    = string
  default = "false"
  description = "Install NVIDIA GPU/vGPU GRID drivers (binary from GCS)"
}

variable "install_aalibrary" {
  type    = string
  default = "false"
  description = "Install AA-SI aalibrary Developer & ML (binary from GCS)"
}

variable "install_echosms" {
  type    = string
  default = "false"
  description = "Install EchoSMs (binary from GCS)"
}

variable "install_echostack" {
  type    = string
  default = "false"
  description = "Install EchoStack (binary from GCS)"
}

variable "install_gcp_utilities" {
  type    = string
  default = "false"
  description = "Install/update GCP Cloud Utilities (Google Cloud SDK)"
}

variable "install_excel" {
  type    = string
  default = "false"
  description = "Install Microsoft Excel via Office Deployment Tool (binary from GCS)"
}

# ── Source ────────────────────────────────────────────────────────────────────
source "googlecompute" "customize_windows" {
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
  winrm_use_ntlm = true
  winrm_port     = 5986
  winrm_timeout  = "90m"

  service_account_email       = var.service_account_email
  zone                        = var.zone
  enable_secure_boot          = true
  enable_integrity_monitoring = true
  enable_vtpm                 = true

  network    = var.vm_network
  subnetwork = var.vm_subnet

  disk_size = 250
  disk_type = "pd-ssd"
  tags      = ["winrm"]

  image_family = var.image_family
  image_name   = var.image_name != "" ? var.image_name : "nmfs-windows-2025-software-{{timestamp}}"
  machine_type = var.machine_type

  image_storage_locations = ["us"]

  metadata = {
    enable-oslogin = "FALSE"
    windows-startup-script-ps1 = <<EOF
net user packer_user "${var.packer_user_password}" /add /y
net localgroup Administrators packer_user /add

reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA /t REG_DWORD /d 1 /f

winrm quickconfig -q
Enable-PSRemoting -Force -SkipNetworkProfileCheck

$cert = New-SelfSignedCertificate -DnsName "packer" -CertStoreLocation Cert:\LocalMachine\My
$thumb = $cert.Thumbprint

Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains "Transport=HTTPS" } | Remove-Item -Recurse -Force
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $thumb -Force

Set-Item -Path WSMan:\localhost\Service\Auth\Basic       -Value $true
Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate   -Value $true
Set-Item -Path WSMan:\localhost\Service\Auth\CredSSP     -Value $false
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false

Set-Item -Path WSMan:\localhost\MaxTimeoutms         -Value 1800000
Set-Item -Path WSMan:\localhost\MaxEnvelopeSizekb    -Value 8192
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="2048"}'
winrm set winrm/config/winrs '@{MaxShellsPerUser="10"}'

netsh advfirewall firewall add rule name="WinRM-HTTPS" dir=in action=allow protocol=TCP localport=5986

Set-Service -Name seclogon -StartupType Manual
Start-Service -Name seclogon

Start-Sleep -Seconds 30

Write-EventLog -LogName Application -Source "GCEMetadataScripts" -EventId 1 -Message "WinRM NTLM setup complete" -EntryType Information
EOF
  }
}

# ── Build ─────────────────────────────────────────────────────────────────────
build {
  sources = ["sources.googlecompute.customize_windows"]

  # Verify WinRM connectivity and apply basic hardening tweaks
  provisioner "powershell" {
    inline = [
      "Write-Host 'Connected as:' $env:USERNAME",
      "Write-Host 'Computer    :' $env:COMPUTERNAME",
      "try { Add-LocalGroupMember -Group 'Administrators' -Member 'packer_user' -ErrorAction Stop } catch {}",
      "Set-Service -Name seclogon -StartupType Manual -ErrorAction SilentlyContinue",
      "Start-Service -Name seclogon -ErrorAction SilentlyContinue",
      "New-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System' -Name 'LocalAccountTokenFilterPolicy' -Value 1 -PropertyType DWord -Force | Out-Null",
      "Set-Item -Path WSMan:\\localhost\\MaxTimeoutms -Value 1800000 -ErrorAction SilentlyContinue",
      "Set-Item -Path WSMan:\\localhost\\MaxEnvelopeSizekb -Value 8192 -ErrorAction SilentlyContinue"
    ]
  }

  # Run Ansible playbook with component flags forwarded as extra-vars
  provisioner "shell-local" {
    environment_vars = [
      "PACKER_PW=${var.packer_user_password}",
      "ZONE=${var.zone}",
      "PROJECT_ID=${var.project_id}",
      "PLAYBOOK_PATH=/workspace/ansible-playbook/main.yml",
      # Component flags forwarded to Ansible
      "INSTALL_ORACLE=${var.install_oracle}",
      "INSTALL_RSTUDIO=${var.install_rstudio}",
      "INSTALL_CONDA=${var.install_conda}",
      "INSTALL_CHROME=${var.install_chrome}",
      "INSTALL_GIT=${var.install_git}",
      "INSTALL_PYTHON=${var.install_python}",
      "INSTALL_JUPYTERLAB=${var.install_jupyterlab}",
      "INSTALL_POWERSHELL_CORE=${var.install_powershell_core}",
      "INSTALL_PYCHARM=${var.install_pycharm}",
      "INSTALL_VISUAL_STUDIO=${var.install_visual_studio}",
      "INSTALL_PARAVIEW=${var.install_paraview}",
      "INSTALL_ECHOVIEW=${var.install_echoview}",
      "INSTALL_MATLAB=${var.install_matlab}",
      "INSTALL_RSTUDIO_PRO=${var.install_rstudio_pro}",
      "INSTALL_POSITRON=${var.install_positron}",
      "INSTALL_ANACONDA=${var.install_anaconda}",
      "INSTALL_GPU_DRIVERS=${var.install_gpu_drivers}",
      "INSTALL_AALIBRARY=${var.install_aalibrary}",
      "INSTALL_ECHOSMS=${var.install_echosms}",
      "INSTALL_ECHOSTACK=${var.install_echostack}",
      "INSTALL_GCP_UTILITIES=${var.install_gcp_utilities}",
      "INSTALL_EXCEL=${var.install_excel}"
    ]
    inline = [
      "set -eu",

      "command -v ansible-playbook >/dev/null 2>&1 || { echo 'ERROR: ansible-playbook not found'; exit 1; }",
      "python3 -c 'import winrm' 2>/dev/null || { echo 'ERROR: pywinrm not installed'; exit 1; }",
      "command -v curl >/dev/null 2>&1 || { echo 'ERROR: curl not found'; exit 1; }",
      "if [ ! -f \"$PLAYBOOK_PATH\" ]; then echo \"ERROR: Playbook not found at $PLAYBOOK_PATH\"; exit 1; fi",

      # Reuse Packer's existing IAP tunnel port
      "TUNNEL_PORT=$(cat /proc/*/cmdline 2>/dev/null | tr '\\0' '\\n' | grep -o 'local-host-port=[^ ]*' | grep -o '[0-9]*$' | head -1 || true)",
      "if [ -z \"$TUNNEL_PORT\" ]; then echo 'ERROR: Could not find IAP tunnel port in /proc'; exit 1; fi",
      "echo \"Found IAP tunnel on port: $TUNNEL_PORT\"",

      "READY=0",
      "ELAPSED=0",
      "for i in $(seq 1 360); do",
      "  HTTP_CODE=$(curl -sk -X POST -o /dev/null -w '%%{http_code}' --max-time 8 \"https://localhost:$TUNNEL_PORT/wsman\" 2>/dev/null || true)",
      "  if [ \"$HTTP_CODE\" = '401' ] || [ \"$HTTP_CODE\" = '411' ] || [ \"$HTTP_CODE\" = '405' ]; then",
      "    READY=1",
      "    echo \"  [attempt $i | elapsed $${ELAPSED}s] WinRM ready (HTTP $HTTP_CODE)\"",
      "    break",
      "  fi",
      "  echo \"  [attempt $i | elapsed $${ELAPSED}s] HTTP '$HTTP_CODE' — retrying in 10s\"",
      "  sleep 10",
      "  ELAPSED=$(($${ELAPSED} + 10))",
      "done",

      "if [ \"$READY\" -eq 0 ]; then echo \"ERROR: WinRM did not respond after 60 minutes\"; exit 1; fi",

      "sleep 60",

      "INVENTORY=/tmp/packer_ansible_hosts.ini",
      "printf '[windows]\\nwinrm_target ansible_host=127.0.0.1 ansible_port=%s\\n\\n[windows:vars]\\nansible_connection=winrm\\nansible_winrm_scheme=https\\nansible_winrm_port=%s\\nansible_winrm_transport=basic\\nansible_winrm_server_cert_validation=ignore\\nansible_winrm_connection_timeout=60\\nansible_winrm_operation_timeout_sec=120\\nansible_winrm_read_timeout_sec=150\\nansible_user=packer_user\\nansible_become=no\\n' \"$TUNNEL_PORT\" \"$TUNNEL_PORT\" > \"$INVENTORY\"",

      "set +e",
      # Pass all component flags as ansible extra-vars
      "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -vvv \\",
      "  -i \"$INVENTORY\" \\",
      "  -e \"ansible_password=$PACKER_PW\" \\",
      "  -e \"install_oracle=$INSTALL_ORACLE\" \\",
      "  -e \"install_rstudio=$INSTALL_RSTUDIO\" \\",
      "  -e \"install_conda=$INSTALL_CONDA\" \\",
      "  -e \"install_chrome=$INSTALL_CHROME\" \\",
      "  -e \"install_git=$INSTALL_GIT\" \\",
      "  -e \"install_python=$INSTALL_PYTHON\" \\",
      "  -e \"install_jupyterlab=$INSTALL_JUPYTERLAB\" \\",
      "  -e \"install_powershell_core=$INSTALL_POWERSHELL_CORE\" \\",
      "  -e \"install_pycharm=$INSTALL_PYCHARM\" \\",
      "  -e \"install_visual_studio=$INSTALL_VISUAL_STUDIO\" \\",
      "  -e \"install_paraview=$INSTALL_PARAVIEW\" \\",
      "  -e \"install_echoview=$INSTALL_ECHOVIEW\" \\",
      "  -e \"install_matlab=$INSTALL_MATLAB\" \\",
      "  -e \"install_rstudio_pro=$INSTALL_RSTUDIO_PRO\" \\",
      "  -e \"install_positron=$INSTALL_POSITRON\" \\",
      "  -e \"install_anaconda=$INSTALL_ANACONDA\" \\",
      "  -e \"install_gpu_drivers=$INSTALL_GPU_DRIVERS\" \\",
      "  -e \"install_aalibrary=$INSTALL_AALIBRARY\" \\",
      "  -e \"install_echosms=$INSTALL_ECHOSMS\" \\",
      "  -e \"install_echostack=$INSTALL_ECHOSTACK\" \\",
      "  -e \"install_gcp_utilities=$INSTALL_GCP_UTILITIES\" \\",
      "  -e \"install_excel=$INSTALL_EXCEL\" \\",
      "  \"$PLAYBOOK_PATH\"",
      "PLAYBOOK_EXIT=$?",
      "set -e",
      "exit $PLAYBOOK_EXIT"
    ]
  }
}
