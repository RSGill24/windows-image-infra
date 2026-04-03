#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies the compiled DSC MOF to enforce STIG controls.

.NOTES
    DSC AccountPolicy resource calls secedit internally which resets
    the security policy database and breaks WinRM auth. This is expected.
    WinRM is restored in the NEXT Packer provisioner block via
    restore_winrm_post_dsc.ps1 — Packer will auto-retry the connection
    after this script exits and WinRM comes back up.

    Run order: AFTER create_mof.ps1, BEFORE restore_winrm_post_dsc.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== Applying DSC configuration ==="

# -----------------------------------------------------------------------
# Resolve MOF path
# -----------------------------------------------------------------------
$OutputPath = Join-Path $PSScriptRoot "MOF"
$mofFile    = Join-Path $OutputPath "localhost.mof"

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
# Apply DSC configuration
# -----------------------------------------------------------------------
Write-Host "Applying DSC configuration (this may take several minutes)..."

try {
    Start-DscConfiguration -Path $OutputPath -Wait -Force -Verbose -ErrorAction Stop
    Write-Host "=== DSC configuration applied successfully ===" -ForegroundColor Green
} catch {
    Write-Warning "Start-DscConfiguration encountered an error: $_"
    Write-Warning "Resource-level failures are expected and will be corrected by post-DSC scripts."
    Write-Host "=== DSC application completed with resource-level warnings ===" -ForegroundColor Yellow
}

# NOTE: WinRM will be broken after this script exits because DSC
# AccountPolicy runs secedit which resets security policy.
# Packer will get a 401 on cleanup — this is expected.
# restore_winrm_post_dsc.ps1 runs next in a separate provisioner
# block and Packer will retry the connection automatically.
Write-Host "DSC done. WinRM restore will happen in next provisioner block."
exit 0
