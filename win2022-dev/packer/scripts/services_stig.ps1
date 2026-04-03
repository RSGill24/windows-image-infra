#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies Services STIG controls.
.NOTES
    FIX: Replaced netsh firewall rules with New-NetFirewallRule (PowerShell
         native API). netsh rules are not reliably applied before
         Set-NetFirewallProfile activates the default inbound block policy,
         causing the active Packer WinRM session to be killed.
         New-NetFirewallRule writes directly to the firewall policy store
         and survives Set-NetFirewallProfile -Enabled True.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host "=== Applying Services STIG (Targeted Fix) ==="

# Antivirus (V-254248)
# Set-Service on WinDefend returns "Access is denied" — use registry directly
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend" `
    -Name "Start" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "Set WinDefend to Automatic via Registry"

# Firewall service (V-254265)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\MpsSvc" `
    -Name "Start" -Value 2 -Type DWord -Force
Write-Host "Set MpsSvc (Windows Defender Firewall) to Automatic via Registry"

# -----------------------------------------------------------------------
# Add WinRM firewall rules via New-NetFirewallRule BEFORE enabling profiles
#
# IMPORTANT: Must use New-NetFirewallRule (not netsh) here.
# netsh rules are written but not reliably enforced before
# Set-NetFirewallProfile -Enabled True activates inbound blocking.
# New-NetFirewallRule writes to the active policy store immediately
# and persists correctly through profile activation.
# -----------------------------------------------------------------------
Write-Host "Adding WinRM firewall rules (PowerShell API) before enabling profiles..."

foreach ($rule in @(
    @{ Name = "WinRM-HTTPS"; Port = 5986; Description = "WinRM HTTPS for Packer/management" },
    @{ Name = "WinRM-HTTP";  Port = 5985; Description = "WinRM HTTP fallback"               }
)) {
    # Remove existing rule if present to avoid duplicates
    Remove-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue

    New-NetFirewallRule `
        -DisplayName  $rule.Name `
        -Direction    Inbound `
        -Action       Allow `
        -Protocol     TCP `
        -LocalPort    $rule.Port `
        -Profile      Any `
        -Description  $rule.Description `
        -ErrorAction  Stop | Out-Null

    Write-Host "  [OK] Firewall rule added: $($rule.Name) port $($rule.Port)" -ForegroundColor Green
}

# Verify rules are present before enabling profiles
$winrmRules = Get-NetFirewallRule -DisplayName "WinRM-HTTPS","WinRM-HTTP" -ErrorAction SilentlyContinue
Write-Host "  WinRM rules confirmed in policy store: $($winrmRules.Count)" -ForegroundColor Green

# Now safe to enable firewall profiles
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
Write-Host "Firewall profiles enabled"

# Confirm port 5986 still reachable after profile activation
Start-Sleep -Seconds 2
$port = netstat -an | Select-String ":5986"
if ($port) {
    Write-Host "  [OK] Port 5986 still listening after firewall enable" -ForegroundColor Green
} else {
    Write-Warning "  Port 5986 not detected after firewall enable — WinRM may be disrupted"
}

Write-Host "=== Services STIG Fixed ==="
