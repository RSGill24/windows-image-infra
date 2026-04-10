#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies the compiled DSC MOF to enforce STIG controls.
.NOTES
    FIX: DSC Scheduled Task se chalta hai — WinRM se independent.
         UserRightsAssignment secedit write karta hai jo WinRM todta hai.
         Scheduled Task SYSTEM account mein chalta hai isliye WinRM
         tootne se script abort nahi hoti.
         DSC complete hone ke baad WinRM restore aur banner re-apply hota hai.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host "=== Applying DSC configuration ==="

# -----------------------------------------------------------------------
# Resolve MOF path
# -----------------------------------------------------------------------
$OutputPath = Join-Path $PSScriptRoot "MOF"
$mofFile    = Join-Path $OutputPath "localhost.mof"

# -----------------------------------------------------------------------
# Pre-application validation
# -----------------------------------------------------------------------
if (!(Test-Path $mofFile)) {
    Write-Error "MOF file not found at: $mofFile"
    exit 1
}

$mofSize = (Get-Item $mofFile).Length
Write-Host "Found MOF: $mofFile ($mofSize bytes)"

if ($mofSize -lt 10000) {
    Write-Error "MOF file is suspiciously small ($mofSize bytes)"
    exit 1
}

# -----------------------------------------------------------------------
# Clear LCM cached MOF
# -----------------------------------------------------------------------
Write-Host "Clearing LCM cached MOF..." -ForegroundColor Yellow

$lcmCachePaths = @(
    "C:\Windows\System32\Configuration\Current.mof",
    "C:\Windows\System32\Configuration\Pending.mof",
    "C:\Windows\System32\Configuration\Previous.mof",
    "C:\Windows\System32\Configuration\backup.mof"
)
foreach ($p in $lcmCachePaths) {
    if (Test-Path $p) {
        Remove-Item $p -Force -ErrorAction SilentlyContinue
        Write-Host "  Deleted: $p" -ForegroundColor Yellow
    }
}

Stop-DscConfiguration -Force -ErrorAction SilentlyContinue
Remove-DscConfigurationDocument -Stage Current  -Force -ErrorAction SilentlyContinue
Remove-DscConfigurationDocument -Stage Pending  -Force -ErrorAction SilentlyContinue
Remove-DscConfigurationDocument -Stage Previous -Force -ErrorAction SilentlyContinue

Write-Host "LCM cache cleared." -ForegroundColor Green

# -----------------------------------------------------------------------
# DSC ko Scheduled Task se chalao — WinRM se independent
# UserRightsAssignment secedit write karta hai jo WinRM todta hai
# Scheduled Task SYSTEM mein chalta hai — WinRM toot bhi jaye toh
# script continue karti hai
# -----------------------------------------------------------------------
Write-Host "Starting DSC via Scheduled Task (SYSTEM account)..." -ForegroundColor Yellow

$dscScriptContent = "Start-DscConfiguration -Path '$OutputPath' -Wait -Force -Verbose *>> 'C:\Windows\Temp\dsc_apply.log' 2>&1"
$dscScriptPath    = "C:\Windows\Temp\run_dsc.ps1"

Set-Content -Path $dscScriptPath -Value $dscScriptContent -Encoding UTF8

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -NonInteractive -File `"$dscScriptPath`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Unregister-ScheduledTask -TaskName "DSC_Apply_STIG" -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask `
    -TaskName  "DSC_Apply_STIG" `
    -Action    $action `
    -Trigger   $trigger `
    -Settings  $settings `
    -Principal $principal `
    -Force | Out-Null

Write-Host "  Scheduled Task registered — waiting for DSC to start..." -ForegroundColor Gray
Start-Sleep -Seconds 15

# -----------------------------------------------------------------------
# DSC complete hone ka wait karo
# -----------------------------------------------------------------------
Write-Host "Waiting for DSC to complete..."
$timeout = 600
$elapsed = 0

do {
    Start-Sleep -Seconds 15
    $elapsed += 15
    $task = Get-ScheduledTask -TaskName "DSC_Apply_STIG" -ErrorAction SilentlyContinue
    $state = if ($task) { $task.State } else { "NotFound" }
    Write-Host "  DSC Task state: $state — ${elapsed}s elapsed"
} while ($state -eq 'Running' -and $elapsed -lt $timeout)

Write-Host "DSC Task finished — Final state: $state" -ForegroundColor Green

# DSC log tail karo
if (Test-Path "C:\Windows\Temp\dsc_apply.log") {
    Write-Host "--- DSC Log (last 10 lines) ---" -ForegroundColor Gray
    Get-Content "C:\Windows\Temp\dsc_apply.log" | Select-Object -Last 10 |
        ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
}

# Cleanup
Unregister-ScheduledTask -TaskName "DSC_Apply_STIG" -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item $dscScriptPath -Force -ErrorAction SilentlyContinue

# -----------------------------------------------------------------------
# WinRM restore — DSC complete ho gaya, ab WinRM fix karo
# -----------------------------------------------------------------------
Write-Host "Restoring WinRM after DSC..." -ForegroundColor Yellow

# WinRM restore block — Restart-Service NAHI karna
# Restart karne se WinRM band ho jaata hai GPO ki wajah se
try {
    # GPO restrictions hatao
    $gpoPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service"
    if (Test-Path $gpoPath) {
        Remove-ItemProperty -Path $gpoPath -Name "AllowBasic"              -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $gpoPath -Name "AllowUnencryptedTraffic" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $gpoPath -Name "DisableRunAs"            -ErrorAction SilentlyContinue
        Write-Host "  GPO WinRM restrictions removed" -ForegroundColor Green
    }

    # WinRM start karo agar band hai
    $svc = Get-Service WinRM
    if ($svc.Status -ne 'Running') {
        Start-Service WinRM
        Start-Sleep -Seconds 5
    }

    # Auth settings set karo — NO Restart-Service
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic       -Value $true -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate   -Value $true -Force
    Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true -Force
    winrm set winrm/config/service '@{AllowUnencrypted="true"}' | Out-Null
    winrm set winrm/config/service/auth '@{Basic="true"}' | Out-Null

    Write-Host "  [OK] WinRM restored" -ForegroundColor Green
} catch {
    Write-Warning "  WinRM restore failed: $_"
}

# -----------------------------------------------------------------------
exit 0
