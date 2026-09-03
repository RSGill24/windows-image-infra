#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host "=== Applying Services STIG (Targeted Fix) ==="

$ErrorCount = 0

# -----------------------------------------------------------------------
# V-254248: Windows Defender Antivirus
# WinDefend is a PPL-protected service on Server 2025 -- registry key is
# also access-controlled. WinDefend is already Running and set to
# Automatic by default on this image; verified and logged only.
# -----------------------------------------------------------------------
Write-Host "`n--- V-254248: Windows Defender (WinDefend) ---"
try {
    $svc = Get-Service -Name WinDefend -ErrorAction Stop
    if ($svc.Status -eq 'Running') {
        Write-Host "  [OK]   WinDefend is Running" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] WinDefend status: $($svc.Status)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [WARN] WinDefend status check: $_" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# V-254265: Windows Defender Firewall must be enabled
# Set-Service fails on MpsSvc (protected) -- use registry directly
# -----------------------------------------------------------------------
Write-Host "`n--- V-254265: Windows Defender Firewall (MpsSvc) ---"
try {
    Set-ItemProperty `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Services\MpsSvc" `
        -Name "Start" -Value 2 -Type DWord -Force
    Write-Host "  [OK]   MpsSvc StartupType set to Automatic via registry" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] MpsSvc registry write failed: $_" -ForegroundColor Yellow
    $ErrorCount++
}

try {
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction Stop
    Write-Host "  [OK]   All firewall profiles enabled" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Set-NetFirewallProfile failed: $_" -ForegroundColor Yellow
    $ErrorCount++
}

# -----------------------------------------------------------------------
# Verify firewall profiles
# -----------------------------------------------------------------------
Write-Host "`n--- Firewall profile verification ---"
try {
    Get-NetFirewallProfile | ForEach-Object {
        $status = if ($_.Enabled) { "[OK]  " } else { "[WARN]" }
        $color  = if ($_.Enabled) { 'Green' } else { 'Yellow' }
        Write-Host "  $status $($_.Name) firewall: Enabled=$($_.Enabled)" -ForegroundColor $color
    }
} catch {
    Write-Host "  [WARN] Could not verify firewall profiles: $_" -ForegroundColor Yellow
}

Write-Host "`n=== Services STIG Fixed (errors: $ErrorCount) ==="
exit $ErrorCount
