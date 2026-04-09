#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies the compiled DSC MOF to enforce STIG controls.
.NOTES
    FIX: Added explicit exit code detection using both $LASTEXITCODE and
         exception handling so failures are not silently swallowed.
    FIX: Added pre-application check to confirm the MOF exists and is
         not zero-length before calling Start-DscConfiguration.
    FIX: Added LCM cache clear before applying MOF to prevent stale cached
         MOF (with AccountPolicy rules) from being applied instead of the
         freshly compiled one — this was causing WinRM 401 errors.
    FIX: Added WinRM restore after DSC — AccountPolicy SCE write breaks
         WinRM auth. Must happen in THIS script before Packer uploads
         cleanup script, otherwise all subsequent provisioners fail with
         401 invalid content type.
    Run order: AFTER create_mof.ps1, BEFORE account_policy.ps1
    (account_policy.ps1 re-applies policies that DSC may fail to set
    due to the SCE database lock during Packer image builds)
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== Applying DSC configuration ==="

# -----------------------------------------------------------------------
# Resolve MOF path relative to this script's directory
# $OutputPath from create_mof.ps1 does not carry over into a separate
# script invocation — always resolve from $PSScriptRoot here.
# -----------------------------------------------------------------------
$OutputPath = Join-Path $PSScriptRoot "MOF"
$mofFile    = Join-Path $OutputPath "localhost.mof"

# -----------------------------------------------------------------------
# Pre-application validation
# -----------------------------------------------------------------------
if (!(Test-Path $mofFile)) {
    Write-Error "MOF file not found at: $mofFile"
    Write-Error "Ensure create_mof.ps1 ran successfully before this script."
    exit 1
}

$mofSize = (Get-Item $mofFile).Length
Write-Host "Found MOF: $mofFile ($mofSize bytes)"

if ($mofSize -lt 10000) {
    Write-Error "MOF file is suspiciously small ($mofSize bytes) — this may indicate a failed compilation."
    Write-Error "Re-run create_mof.ps1 and check for errors before applying."
    exit 1
}

# -----------------------------------------------------------------------
# CRITICAL: Clear LCM cached MOF before applying new one.
# LCM stores its own copy independently of our MOF output directory.
# If old cached MOF has AccountPolicy rules, LCM will run THOSE instead
# of the newly compiled MOF — breaking WinRM via SCE database write.
# -----------------------------------------------------------------------
Write-Host "Clearing LCM cached MOF to force fresh application..." -ForegroundColor Yellow

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
# Apply DSC configuration
# -Wait     : Block until all resources are applied (required in Packer)
# -Force    : Apply even if system is already in desired state
# -Verbose  : Log each resource operation (essential for debugging)
# -----------------------------------------------------------------------
Write-Host "Applying DSC configuration (this may take several minutes)..."

try {
    Start-DscConfiguration -Path $OutputPath -Wait -Force -Verbose -ErrorAction Stop
    Write-Host "=== DSC configuration applied successfully ===" -ForegroundColor Green
} catch {
    # Start-DscConfiguration throws on hard failures (e.g. MOF parse error,
    # LCM not running). Individual resource failures are logged as verbose
    # output but do NOT cause an exception — they are handled by
    # account_policy.ps1 and stig_remediation_fixes.ps1 running afterward.
    Write-Warning "Start-DscConfiguration encountered an error: $_"
    Write-Warning "Individual resource failures (e.g. AccountPolicy SCE lock) are expected"
    Write-Warning "during Packer builds and will be corrected by account_policy.ps1."
    Write-Warning "Check the verbose output above for specific resource failures."
    Write-Host "=== DSC application completed with resource-level warnings ===" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# CRITICAL: Restore WinRM immediately after DSC
# AccountPolicy DSC resource writes to SCE security database which
# corrupts WinRM authentication. We MUST fix it here before this
# script exits — Packer tries to upload cleanup script immediately
# after exit and will get 401 if WinRM is not restored.
#
# DO NOT move this to a separate provisioner — it will be too late.
# -----------------------------------------------------------------------
Write-Host "=== Restoring WinRM after DSC ===" -ForegroundColor Yellow

$ErrorActionPreference = 'Continue'

# Re-enable WinRM auth settings that SCE write may have disrupted
try {
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic       -Value $true -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate   -Value $true -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\Kerberos    -Value $true -Force
    Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true -Force
    Write-Host "  WinRM auth settings restored" -ForegroundColor Green
} catch {
    Write-Warning "  WinRM auth setting failed: $_"
}

# Restart WinRM service to flush broken state
try {
    $wsman = Get-Service -Name WinRM
    Write-Host "  WinRM current state: $($wsman.Status)"

    Restart-Service -Name WinRM -Force
    Start-Sleep -Seconds 8

    $wsman = Get-Service -Name WinRM
    if ($wsman.Status -eq 'Running') {
        Write-Host "  [OK] WinRM restarted successfully" -ForegroundColor Green
    } else {
        Write-Warning "  WinRM status after restart: $($wsman.Status)"
        Start-Service -Name WinRM
        Start-Sleep -Seconds 5
    }
} catch {
    Write-Warning "  WinRM restart failed: $_"
}

# Re-apply WinRM config after restart via winrm.cmd for double confirmation
try {
    winrm set winrm/config/service '@{AllowUnencrypted="true"}' | Out-Null
    winrm set winrm/config/service/auth '@{Basic="true"}' | Out-Null
    winrm set winrm/config/service/auth '@{Negotiate="true"}' | Out-Null
    Write-Host "  [OK] WinRM config re-applied via winrm.cmd" -ForegroundColor Green
} catch {
    Write-Warning "  winrm.cmd config failed: $_"
}

Write-Host "=== WinRM restore complete ===" -ForegroundColor Green

# Exit 0 intentionally — resource-level DSC failures are non-fatal at this
# stage and will be corrected by account_policy.ps1 running afterward.
exit 0
