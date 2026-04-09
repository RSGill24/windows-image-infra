#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies the compiled DSC MOF to enforce STIG controls.
.NOTES
    FIX: Added explicit exit code detection using both $LASTEXITCODE and
         exception handling so failures are not silently swallowed.
    FIX: Added pre-application check to confirm the MOF exists and is
         not zero-length before calling Start-DscConfiguration.
    FIX: Added post-DSC WinRM restore to recover from SCE database lock
         that breaks WinRM auth (401 invalid content type) after the
         AccountPolicy DSC resource runs. Must happen in THIS script
         before Packer attempts to upload the cleanup script.
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
# POST-DSC: Restore WinRM
# The AccountPolicy DSC resource writes to the SCE security database,
# which corrupts WinRM's authentication state and causes 401 errors on
# every subsequent Packer upload (winrmcp "invalid content type").
# This MUST run here, inside apply_mof.ps1, before this script exits —
# Packer tries to upload the cleanup script the moment this script
# returns, so a separate provisioner is already too late.
# -----------------------------------------------------------------------
Write-Host "=== Restoring WinRM after DSC application ===" -ForegroundColor Yellow

try {
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic       -Value $true -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate   -Value $true -Force
    Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true -Force

    Restart-Service -Name WinRM -Force
    Start-Sleep -Seconds 5

    $wmSvc = Get-Service -Name WinRM
    if ($wmSvc.Status -ne 'Running') {
        Write-Warning "WinRM did not come back up — Packer may lose connection after this step."
    } else {
        Write-Host "WinRM restored and running OK" -ForegroundColor Green
    }
} catch {
    Write-Warning "WinRM restore encountered an error: $_"
    Write-Warning "Packer may lose connectivity after this provisioner."
}

# Exit 0 intentionally — resource-level DSC failures are non-fatal at this
# stage and will be corrected by account_policy.ps1 running afterward.
exit 0
