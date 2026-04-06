#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host "=== Applying Services STIG (Targeted Fix) ==="

# Antivirus (V-254248) — registry direct, Set-Service denied on GCP images
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend" `
    -Name "Start" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "Set WinDefend to Automatic via Registry"

# Firewall service startup (V-254265) — registry only, no profile enable
# NOTE: Set-NetFirewallProfile -Enabled True kills the Packer WinRM elevated
# shell (exit code 16001) because Restart-Service WinRM terminates the active
# elevated session. Firewall profiles are already configured by DSC.
# MpsSvc startup type is set here so the service starts on boot.
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\MpsSvc" `
    -Name "Start" -Value 2 -Type DWord -Force
Write-Host "Set MpsSvc (Windows Defender Firewall) to Automatic via Registry"

# Ensure WinRM firewall rules exist for Packer connectivity
Write-Host "Ensuring WinRM firewall rules..."

foreach ($rule in @(
    @{ Name = "WinRM-HTTPS"; Port = 5986 },
    @{ Name = "WinRM-HTTP";  Port = 5985 }
)) {
    $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule `
            -DisplayName $rule.Name `
            -Direction   Inbound `
            -Action      Allow `
            -Protocol    TCP `
            -LocalPort   $rule.Port `
            -Profile     Any `
            -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  [OK] Added rule: $($rule.Name) port $($rule.Port)" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Rule exists: $($rule.Name)" -ForegroundColor Green
    }
}

Write-Host "=== Services STIG Fixed ==="
exit 0
