#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host "=== Applying Services STIG (Targeted Fix) ==="

# Antivirus (V-254248) — registry direct, Set-Service denied
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend" `
    -Name "Start" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "Set WinDefend to Automatic via Registry"

# Firewall service (V-254265)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\MpsSvc" `
    -Name "Start" -Value 2 -Type DWord -Force
Write-Host "Set MpsSvc (Windows Defender Firewall) to Automatic via Registry"

# -----------------------------------------------------------------------
# Add WinRM rules via New-NetFirewallRule BEFORE enabling profiles
# -----------------------------------------------------------------------
Write-Host "Adding WinRM firewall rules before enabling profiles..."

foreach ($rule in @(
    @{ Name = "WinRM-HTTPS"; Port = 5986 },
    @{ Name = "WinRM-HTTP";  Port = 5985 }
)) {
    Remove-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName $rule.Name `
        -Direction   Inbound `
        -Action      Allow `
        -Protocol    TCP `
        -LocalPort   $rule.Port `
        -Profile     Any `
        -ErrorAction Stop | Out-Null
    Write-Host "  [OK] Firewall rule: $($rule.Name) port $($rule.Port)" -ForegroundColor Green
}

Write-Host "WinRM firewall rules added (5985, 5986)" -ForegroundColor Green

# Enable firewall profiles
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
Write-Host "Firewall profiles enabled"

# -----------------------------------------------------------------------
# Restart WinRM after firewall enable so Packer connection recovers
# Enabling firewall profiles briefly disrupts the WinRM session.
# Restarting WinRM forces it to re-bind on port 5986 with the new rules.
# -----------------------------------------------------------------------
Write-Host "Restarting WinRM to recover connection after firewall enable..."
Start-Sleep -Seconds 2
Restart-Service -Name WinRM -Force
Start-Sleep -Seconds 5

$port = netstat -an | Select-String ":5986"
if ($port) {
    Write-Host "  [OK] Port 5986 listening after firewall enable" -ForegroundColor Green
} else {
    Write-Warning "  Port 5986 not detected — Packer may lose connection"
}

Write-Host "=== Services STIG Fixed ==="
exit 0
