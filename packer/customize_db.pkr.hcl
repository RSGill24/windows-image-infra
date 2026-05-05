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

  # Step 2: Open a dedicated IAP tunnel on a fixed port and run ansible-playbook.
  #
  # IMPORTANT: Packer shell-local uses /bin/sh by default.
  # 'set -o pipefail' is bash-only and causes sh to exit with code 2 immediately.
  # Fix: set interpreter = ["/bin/bash", "-c"] to force bash.
  provisioner "shell-local" {
    # Force bash — /bin/sh does not support pipefail and will exit code 2
    interpreter = ["/bin/bash", "-c"]

    environment_vars = [
      "PACKER_PW=${var.packer_user_password}",
      "DATABASE_TYPE=${var.database_type}",
      "ZONE=${var.zone}",
      "PROJECT_ID=${var.project_id}",
      "PLAYBOOK_PATH=${var.installation_source_dir}/../ansible-playbook/database_installation.yml"
    ]
    inline = [
      "set -euo pipefail",

      # ------------------------------------------------------------------
      # Pre-flight checks — fail fast before the VM is even touched
      # ------------------------------------------------------------------
      "command -v ansible-playbook >/dev/null 2>&1 || { echo 'ERROR: ansible-playbook not found on local machine'; exit 1; }",
      "python3 -c 'import winrm' 2>/dev/null || { echo 'ERROR: pywinrm not installed. Run: pip install pywinrm'; exit 1; }",
      "if [ ! -f \"$PLAYBOOK_PATH\" ]; then echo \"ERROR: Playbook not found at $PLAYBOOK_PATH\"; exit 1; fi",
      "echo \"Pre-flight OK — playbook confirmed at: $PLAYBOOK_PATH\"",

      # ------------------------------------------------------------------
      # 1. Detect the instance name via gcloud
      # ------------------------------------------------------------------
      "echo 'Detecting instance name from gcloud...'",
      "INSTANCE_NAME=$(gcloud compute instances list --filter=\"tags.items:winrm AND zone:($ZONE)\" --format=\"value(name)\" --project=\"$PROJECT_ID\" | head -1)",
      "if [ -z \"$INSTANCE_NAME\" ]; then echo 'ERROR: Could not detect instance name'; gcloud compute instances list --filter=\"zone:($ZONE)\" --format=\"table(name,status)\" --project=\"$PROJECT_ID\" || true; exit 1; fi",
      "echo \"Instance name: $INSTANCE_NAME\"",

      # ------------------------------------------------------------------
      # 2. Open IAP tunnel on fixed port 15986
      #    Trap fires on any exit — success, failure, or interruption —
      #    so the tunnel is always cleaned up.
      # ------------------------------------------------------------------
      "echo 'Opening dedicated IAP tunnel on port 15986...'",
      "gcloud compute start-iap-tunnel \"$INSTANCE_NAME\" 5986 --local-host-port=127.0.0.1:15986 --zone=\"$ZONE\" --project=\"$PROJECT_ID\" &",
      "TUNNEL_PID=$!",
      "trap 'echo Closing IAP tunnel...; kill \"$TUNNEL_PID\" 2>/dev/null || true; wait \"$TUNNEL_PID\" 2>/dev/null || true' EXIT",
      "echo \"Tunnel PID: $TUNNEL_PID\"",

      # ------------------------------------------------------------------
      # 3. Wait for tunnel to be ready (poll up to 60s)
      # ------------------------------------------------------------------
      "echo 'Waiting for tunnel to be ready...'",
      "READY=0",
      "for i in $(seq 1 30); do nc -z 127.0.0.1 15986 2>/dev/null && READY=1 && break || sleep 2; done",
      "if [ \"$READY\" -eq 0 ]; then echo 'ERROR: IAP tunnel did not become ready in 60s'; exit 1; fi",
      "echo 'Tunnel ready on 127.0.0.1:15986'",

      # ------------------------------------------------------------------
      # 4. Write Ansible inventory using printf
      #    ansible_password is passed via -e flag only, not written to disk
      # ------------------------------------------------------------------
      "INVENTORY=/tmp/packer_ansible_hosts.ini",
      "printf '[windows]\\nwinrm_target ansible_host=127.0.0.1 ansible_port=15986\\n\\n[windows:vars]\\nansible_connection=winrm\\nansible_winrm_scheme=https\\nansible_winrm_port=15986\\nansible_winrm_transport=basic\\nansible_winrm_server_cert_validation=ignore\\nansible_user=packer_user\\nansible_become=no\\n' > \"$INVENTORY\"",
      "printf 'database_type=%s\\n' \"$DATABASE_TYPE\" >> \"$INVENTORY\"",
      "echo 'Inventory written:'",
      "cat \"$INVENTORY\"",

      # ------------------------------------------------------------------
      # 5. Run the Ansible playbook
      #    set +e around the call so $? is captured before set -e can
      #    kill the shell on a non-zero exit code.
      # ------------------------------------------------------------------
      "echo 'Running Ansible playbook...'",
      "set +e",
      "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i \"$INVENTORY\" -e \"ansible_password=$PACKER_PW\" -e \"database_type=$DATABASE_TYPE\" \"$PLAYBOOK_PATH\"",
      "PLAYBOOK_EXIT=$?",
      "set -e",
      "echo \"Playbook finished with exit code: $PLAYBOOK_EXIT\"",

      # Trap handles tunnel cleanup. Exit with playbook's code.
      "exit $PLAYBOOK_EXIT"
    ]
  }
}