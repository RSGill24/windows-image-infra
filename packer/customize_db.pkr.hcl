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

  # Step 1: Confirm WinRM connection and prep the Windows environment
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

  # Step 2: Run ansible-playbook via Packer's EXISTING IAP tunnel.
  #
  # KEY INSIGHT from logs:
  #   Packer already opened an IAP tunnel to connect via WinRM and it is
  #   still running while this shell-local provisioner executes.
  #   Opening a SECOND tunnel to port 5986 on the same VM races against
  #   gcloud's own 60s connection test and always loses.
  #
  # Fix:
  #   Find the local port Packer's existing tunnel is bound to using ss/lsof,
  #   then point Ansible at 127.0.0.1:<that_port>. No second tunnel needed.
  provisioner "shell-local" {
    environment_vars = [
      "PACKER_PW=${var.packer_user_password}",
      "DATABASE_TYPE=${var.database_type}",
      "ZONE=${var.zone}",
      "PROJECT_ID=${var.project_id}",
      "PLAYBOOK_PATH=${var.installation_source_dir}/../ansible-playbook/database_installation.yml"
    ]
    inline = [
      "set -eu",

      # ------------------------------------------------------------------
      # Pre-flight checks
      # ------------------------------------------------------------------
      "command -v ansible-playbook >/dev/null 2>&1 || { echo 'ERROR: ansible-playbook not found'; exit 1; }",
      "python3 -c 'import winrm' 2>/dev/null || { echo 'ERROR: pywinrm not installed. Run: pip install pywinrm'; exit 1; }",
      "if [ ! -f \"$PLAYBOOK_PATH\" ]; then echo \"ERROR: Playbook not found at $PLAYBOOK_PATH\"; exit 1; fi",
      "echo \"Pre-flight OK — playbook confirmed at: $PLAYBOOK_PATH\"",

      # ------------------------------------------------------------------
      # Find the local port of Packer's existing IAP tunnel.
      #
      # Packer's tunnel process looks like:
      #   gcloud compute start-iap-tunnel <instance> 5986 --local-host-port=127.0.0.1:<PORT>
      #
      # We extract <PORT> from the running process args.
      # ------------------------------------------------------------------
      "echo 'Finding Packer IAP tunnel port...'",
      "TUNNEL_PORT=$(ps aux | grep 'start-iap-tunnel' | grep -v grep | grep -o 'local-host-port=127.0.0.1:[0-9]*' | cut -d: -f2 | head -1)",

      # Fallback: use ss to find any local port forwarding to 5986 on 127.0.0.1
      "if [ -z \"$TUNNEL_PORT\" ]; then",
      "  echo 'ps grep failed, trying ss fallback...'",
      "  TUNNEL_PORT=$(ss -tlnp 2>/dev/null | awk '/127\\.0\\.0\\.1/{print $4}' | cut -d: -f2 | grep -v '^5986$' | head -1)",
      "fi",

      "if [ -z \"$TUNNEL_PORT\" ]; then echo 'ERROR: Could not find Packer IAP tunnel port'; ps aux | grep iap || true; exit 1; fi",
      "echo \"Found Packer IAP tunnel on local port: $TUNNEL_PORT\"",

      # Verify the port is actually open
      "nc -z 127.0.0.1 \"$TUNNEL_PORT\" 2>/dev/null || { echo \"ERROR: Port $TUNNEL_PORT is not reachable\"; exit 1; }",
      "echo \"Port $TUNNEL_PORT confirmed reachable\"",

      # ------------------------------------------------------------------
      # Write Ansible inventory pointing at Packer's existing tunnel port
      # ------------------------------------------------------------------
      "INVENTORY=/tmp/packer_ansible_hosts.ini",
      "printf '[windows]\\nwinrm_target ansible_host=127.0.0.1 ansible_port=%s\\n\\n[windows:vars]\\nansible_connection=winrm\\nansible_winrm_scheme=https\\nansible_winrm_port=%s\\nansible_winrm_transport=basic\\nansible_winrm_server_cert_validation=ignore\\nansible_user=packer_user\\nansible_become=no\\n' \"$TUNNEL_PORT\" \"$TUNNEL_PORT\" > \"$INVENTORY\"",
      "printf 'database_type=%s\\n' \"$DATABASE_TYPE\" >> \"$INVENTORY\"",
      "echo 'Inventory written:'",
      "cat \"$INVENTORY\"",

      # ------------------------------------------------------------------
      # Run the Ansible playbook
      # set +e so $? is captured before the shell exits on failure
      # ------------------------------------------------------------------
      "echo 'Running Ansible playbook...'",
      "set +e",
      "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i \"$INVENTORY\" -e \"ansible_password=$PACKER_PW\" -e \"database_type=$DATABASE_TYPE\" \"$PLAYBOOK_PATH\"",
      "PLAYBOOK_EXIT=$?",
      "set -e",
      "echo \"Playbook finished with exit code: $PLAYBOOK_EXIT\"",

      "exit $PLAYBOOK_EXIT"
    ]
  }
}