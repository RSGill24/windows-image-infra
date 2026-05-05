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
  # Root cause of all previous failures:
  #   Packer opens its IAP tunnel on a RANDOM local port.
  #   The Ansible plugin always tries 127.0.0.1:5986 which is never the right port.
  #   Result: "Connection refused" every time.
  #
  # Fix:
  #   1. Find the running instance name from Packer's own IAP tunnel process
  #      (gcloud start-iap-tunnel is still running while provisioners execute).
  #   2. Open a SECOND IAP tunnel on a fixed known port (15986).
  #   3. Write an Ansible inventory pointing at 127.0.0.1:15986.
  #   4. Run ansible-playbook directly — no Packer Ansible plugin involved.
  provisioner "shell-local" {
    environment_vars = [
      "PACKER_PW=${var.packer_user_password}",
      "DATABASE_TYPE=${var.database_type}",
      "ZONE=${var.zone}",
      "PROJECT_ID=${var.project_id}",
      "PLAYBOOK_PATH=${var.installation_source_dir}/../ansible-playbook/database_installation.yml"
    ]
    inline = [
      "set -e",

      # The gcloud start-iap-tunnel process is still running while provisioners
      # execute. Extract the instance name from its command line.
      "echo 'Detecting instance name from running IAP tunnel process...'",
      "INSTANCE_NAME=$(ps aux | grep 'start-iap-tunnel' | grep -v grep | awk '{for(i=1;i<=NF;i++) if($i==\"start-iap-tunnel\") print $(i+1)}' | head -1)",
      "if [ -z \"$INSTANCE_NAME\" ]; then echo 'ERROR: Could not detect instance name from IAP tunnel process'; ps aux | grep -i iap || true; exit 1; fi",
      "echo \"Instance name: $INSTANCE_NAME\"",

      # Open a second IAP tunnel on fixed port 15986
      "echo 'Opening dedicated IAP tunnel on port 15986...'",
      "gcloud compute start-iap-tunnel \"$INSTANCE_NAME\" 5986 --local-host-port=127.0.0.1:15986 --zone=$ZONE --project=$PROJECT_ID &",
      "TUNNEL_PID=$!",
      "echo \"Tunnel PID: $TUNNEL_PID\"",

      # Wait for tunnel to be ready (poll up to 30s)
      "echo 'Waiting for tunnel to be ready...'",
      "READY=0",
      "for i in $(seq 1 15); do nc -z 127.0.0.1 15986 2>/dev/null && READY=1 && break || sleep 2; done",
      "if [ $READY -eq 0 ]; then echo 'ERROR: IAP tunnel did not become ready in 30s'; kill $TUNNEL_PID || true; exit 1; fi",
      "echo 'Tunnel ready on 127.0.0.1:15986'",

      # Write Ansible inventory
      "INVENTORY=/tmp/packer_ansible_hosts.ini",
      "cat > $INVENTORY << 'INI'",
      "[windows]",
      "winrm_target ansible_host=127.0.0.1 ansible_port=15986",
      "",
      "[windows:vars]",
      "ansible_connection=winrm",
      "ansible_winrm_scheme=https",
      "ansible_winrm_port=15986",
      "ansible_winrm_transport=basic",
      "ansible_winrm_server_cert_validation=ignore",
      "ansible_user=packer_user",
      "ansible_become=no",
      "INI",
      "echo \"ansible_password=$PACKER_PW\" >> $INVENTORY",
      "echo \"database_type=$DATABASE_TYPE\" >> $INVENTORY",
      "echo 'Inventory written:'",
      "cat $INVENTORY",

      # Run the playbook
      "echo 'Running Ansible playbook...'",
      "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i $INVENTORY -e ansible_password=$PACKER_PW -e database_type=$DATABASE_TYPE $PLAYBOOK_PATH",
      "PLAYBOOK_EXIT=$?",

      # Clean up tunnel
      "echo 'Closing IAP tunnel...'",
      "kill $TUNNEL_PID 2>/dev/null || true",
      "wait $TUNNEL_PID 2>/dev/null || true",

      "exit $PLAYBOOK_EXIT"
    ]
  }
}