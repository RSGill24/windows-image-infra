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

  # Step 2: Run ansible-playbook reusing Packer's existing IAP tunnel.
  #
  # PROBE STRATEGY — curl, not nc:
  #   The IAP tunnel is an HTTP/2 CONNECT proxy. `nc -z` does a raw TCP
  #   connect and always reports the port as closed even when the tunnel is
  #   working (WinRM already proved it works in Step 1).
  #   `curl --insecure https://localhost:PORT/wsman` sends a real HTTPS
  #   request through the tunnel. WinRM replies HTTP 401 (auth required)
  #   when it is alive — that 401 is our green light to proceed.
  #
  # TIMING — breaks IMMEDIATELY on success, does NOT wait 60 minutes:
  #   Checks every 10 seconds. If IAP connects in 2 minutes, the loop
  #   breaks at that exact moment and Ansible starts right away.
  #   60 minutes is only the hard ceiling if something is truly broken.
  provisioner "shell-local" {
    environment_vars = [
      "PACKER_PW=${var.packer_user_password}",
      "DATABASE_TYPE=${var.database_type}",
      "ZONE=${var.zone}",
      "PROJECT_ID=${var.project_id}",
      "PLAYBOOK_PATH=/workspace/ansible-playbook/database_installation.yml"
    ]
    inline = [
      "set -eu",

      # ------------------------------------------------------------------
      # Pre-flight checks
      # ------------------------------------------------------------------
      "command -v ansible-playbook >/dev/null 2>&1 || { echo 'ERROR: ansible-playbook not found'; exit 1; }",
      "python3 -c 'import winrm' 2>/dev/null || { echo 'ERROR: pywinrm not installed'; exit 1; }",
      "command -v curl >/dev/null 2>&1 || { echo 'ERROR: curl not found'; exit 1; }",
      "if [ ! -f \"$PLAYBOOK_PATH\" ]; then echo \"ERROR: Playbook not found at $PLAYBOOK_PATH\"; exit 1; fi",
      "echo \"Pre-flight OK — playbook confirmed at: $PLAYBOOK_PATH\"",

      # ------------------------------------------------------------------
      # Find Packer's IAP tunnel port from /proc cmdline
      # ------------------------------------------------------------------
      "echo 'Finding Packer IAP tunnel port...'",
      "TUNNEL_PORT=$(cat /proc/*/cmdline 2>/dev/null | tr '\\0' '\\n' | grep -o 'local-host-port=[^ ]*' | grep -o '[0-9]*$' | head -1 || true)",

      "if [ -z \"$TUNNEL_PORT\" ]; then",
      "  echo 'ERROR: Could not find IAP tunnel port in /proc'",
      "  cat /proc/*/cmdline 2>/dev/null | tr '\\0' '\\n' | grep -i 'iap\\|local-host-port' || true",
      "  exit 1",
      "fi",

      "echo \"Found IAP tunnel on port: $TUNNEL_PORT\"",

      # ------------------------------------------------------------------
      # Poll WinRM every 10 seconds.
      # BREAKS IMMEDIATELY the moment IAP responds successfully.
      # Maximum 360 attempts x 10s = 60 minutes hard ceiling.
      #
      # curl flags:
      #   -s            silent
      #   -k            skip SSL cert validation (self-signed on Windows)
      #   -o /dev/null  discard response body
      #   -w '%%{http_code}'  capture only the HTTP status code
      #   --max-time 8  abort this single attempt after 8s (keeps us
      #                 within the 10s interval even on a hung tunnel)
      #
      # Success condition: HTTP 401 (WinRM alive, wants credentials)
      #                 or HTTP 200 (WinRM alive, already authed)
      # ------------------------------------------------------------------
      "echo \"Polling IAP tunnel on localhost:$TUNNEL_PORT every 10s — max 60 min. Proceeds immediately on success.\"",
      "READY=0",
      "ELAPSED=0",
      "for i in $(seq 1 360); do",
      "  HTTP_CODE=$(curl -sk -o /dev/null -w '%%{http_code}' --max-time 8 \"https://localhost:$TUNNEL_PORT/wsman\" 2>/dev/null || true)",
      "  if [ \"$HTTP_CODE\" = '401' ] || [ \"$HTTP_CODE\" = '200' ]; then",
      "    READY=1",
      "    echo \"  [attempt $i | elapsed ${ELAPSED}s] SUCCESS — WinRM responded HTTP $HTTP_CODE. Starting Ansible immediately.\"",
      "    break",
      "  fi",
      "  echo \"  [attempt $i | elapsed ${ELAPSED}s] HTTP '$HTTP_CODE' — tunnel not ready yet, retrying in 10s...\"",
      "  sleep 10",
      "  ELAPSED=$((ELAPSED + 10))",
      "done",

      "if [ \"$READY\" -eq 0 ]; then",
      "  echo \"ERROR: WinRM on localhost:$TUNNEL_PORT did not respond after 60 minutes (360 attempts).\"",
      "  echo \"Last HTTP code received: $HTTP_CODE\"",
      "  echo \"Active IAP tunnel processes:\"",
      "  cat /proc/*/cmdline 2>/dev/null | tr '\\0' '\\n' | grep -i 'iap\\|local-host-port\\|start-iap' || true",
      "  exit 1",
      "fi",

      # ------------------------------------------------------------------
      # Write Ansible inventory
      # ------------------------------------------------------------------
      "INVENTORY=/tmp/packer_ansible_hosts.ini",
      "printf '[windows]\\nwinrm_target ansible_host=127.0.0.1 ansible_port=%s\\n\\n[windows:vars]\\nansible_connection=winrm\\nansible_winrm_scheme=https\\nansible_winrm_port=%s\\nansible_winrm_transport=basic\\nansible_winrm_server_cert_validation=ignore\\nansible_user=packer_user\\nansible_become=no\\n' \"$TUNNEL_PORT\" \"$TUNNEL_PORT\" > \"$INVENTORY\"",
      "printf 'database_type=%s\\n' \"$DATABASE_TYPE\" >> \"$INVENTORY\"",
      "echo 'Inventory written:'",
      "cat \"$INVENTORY\"",

      # ------------------------------------------------------------------
      # Run the Ansible playbook
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