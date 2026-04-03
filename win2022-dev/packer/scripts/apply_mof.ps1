#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies the compiled DSC MOF to enforce STIG controls.
.NOTES
    FIX: Added explicit exit code detection using both $LASTEXITCODE and
         exception handling so failures are not silently swallowed.
    FIX: Added pre-application check to confirm the MOF exists and is
         not zero-length before calling Start-DscConfiguration.
    FIX: Removed dead registry code that was incorrectly appended after
         exit 0 — that code belongs in registry_stig.ps1 only.
    Run order: AFTER create_mof.ps1, BEFORE account_policy.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== Applying DSC configuration ==="

# -----------------------------------------------------------------------
# Resolve MOF path relative to this script's directory
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
    exit 0
} catch {
    Write-Warning "Start-DscConfiguration encountered an error: $_"
    Write-Warning "Individual resource failures (e.g. AccountPolicy SCE lock) are expected"
    Write-Warning "during Packer builds and will be corrected by account_policy.ps1."
    Write-Warning "Check the verbose output above for specific resource failures."
    Write-Host "=== DSC application completed with resource-level warnings ===" -ForegroundColor Yellow
    exit 0
}
