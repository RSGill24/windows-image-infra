#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies Services STIG controls.
.NOTES
    FIX: WinRM firewall rules for port 5985 and 5986 are explicitly added
         BEFORE Set-NetFirewallProfile enables all profiles. Without this,
         enabling the firewall kills the active Packer WinRM session and
         all subsequent scripts in the pipeline are silently skipped.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host "=== Applying Services STIG (Targeted Fix) ==="

# Antivirus (V-254248)
Set-Service -Name WinDefend -StartupType Automatic
Start-Service WinDefend -ErrorAction SilentlyContinue

# Firewall service (V-254265)
# Use registry directly — Set-Service on MpsSvc returns "Access is denied"
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\MpsSvc" `
    -Name "Start" -Value 2 -Type DWord -Force
Write-Host "Set MpsSvc (Windows Defender Firewall) to Automatic via Registry"

# -----------------------------------------------------------------------
# Preserve WinRM connectivity BEFORE enabling firewall profiles
# Set-NetFirewallProfile activates all inbound block rules. Without
# explicit allow rules for 5985/5986, Packer's WinRM session is killed
# here and no subsequent scripts run inside the build pipeline.
# -----------------------------------------------------------------------
Write-Host "Adding WinRM firewall rules before enabling profiles..."

netsh advfirewall firewall delete rule name="WinRM-HTTPS" | Out-Null
netsh advfirewall firewall delete rule name="WinRM-HTTP"  | Out-Null

netsh advfirewall firewall add rule name="WinRM-HTTPS" dir=in action=allow protocol=TCP localport=5986
netsh advfirewall firewall add rule name="WinRM-HTTP"  dir=in action=allow protocol=TCP localport=5985
Write-Host "WinRM firewall rules added (5985, 5986)" -ForegroundColor Green

# Now safe to enable firewall profiles
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
Write-Host "Firewall profiles enabled"

Write-Host "=== Services STIG Fixed ==="
exit 0
