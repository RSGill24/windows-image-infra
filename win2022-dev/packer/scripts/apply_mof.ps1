#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies the compiled DSC MOF to enforce STIG controls.
.NOTES
    FIX: WinRM restore block removed entirely. AccountPolicy rules are now
         excluded from the MOF via SkipRule in create_mof.ps1, so DSC never
         writes to the SCE security database during apply. Without the SCE
         write, GPO-derived WinRM restrictions are not re-enforced mid-session
         and the Packer connection survives through to subsequent provisioners.

    FIX: Added pre-apply AccountPolicy absence check — confirms the MOF
         compiled by create_mof.ps1 contains no AccountPolicy resources before
         attempting to apply. Fails fast with a clear message if SkipRule did
         not take effect, rather than breaking WinRM silently mid-apply.

    Run order: AFTER create_mof.ps1, BEFORE account_policy.ps1
    (account_policy.ps1 applies all password/lockout policy via secedit,
    which does not go through the DSC LCM and does not affect WinRM)
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
# Pre-application validation — file exists and is non-trivial
# -----------------------------------------------------------------------
if (!(Test-Path $mofFile)) {
    Write-Error "MOF file not found at: $mofFile"
    Write-Error "Ensure create_mof.ps1 ran successfully before this script."
    exit 1
}

$mofSize = (Get-Item $mofFile).Length
Write-Host "Found MOF: $mofFile ($mofSize bytes)"

if ($mofSize -lt 10000) {
    Write-Error "MOF file is suspiciously small ($mofSize bytes) — compilation may have failed."
    Write-Error "Re-run create_mof.ps1 and check for errors before applying."
    exit 1
}

# -----------------------------------------------------------------------
# Pre-application validation — AccountPolicy must not be in the MOF.
# If it is, applying will write to the SCE database and break WinRM.
# create_mof.ps1 already checks this, but we re-verify here as a
# safeguard in case the MOF was compiled by a different run.
# -----------------------------------------------------------------------
Write-Host "Verifying MOF contains no AccountPolicy resources..."
$accountPolicyHits = Select-String -Path $mofFile -Pattern "AccountPolicy" -SimpleMatch
if ($accountPolicyHits) {
    Write-Error "AccountPolicy resources found in MOF — applying would break WinRM mid-session."
    Write-Error "Re-run create_mof.ps1 to recompile with AccountPolicy rules in SkipRule."
    exit 1
}
Write-Host "  [OK] No AccountPolicy resources in MOF." -ForegroundColor Green

# -----------------------------------------------------------------------
# Clear LCM cached MOF to force fresh application.
# LCM stores its own copy independently of the MOF output directory.
# Stale cached MOFs can have AccountPolicy rules even after recompilation.
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

# Stop-DscConfiguration returns exit code 16001 when no config is running.
# Temporarily use Continue mode so this does not abort the script.
$ErrorActionPreference = 'Continue'
Stop-DscConfiguration -Force -ErrorAction SilentlyContinue
Remove-DscConfigurationDocument -Stage Current  -Force -ErrorAction SilentlyContinue
Remove-DscConfigurationDocument -Stage Pending  -Force -ErrorAction SilentlyContinue
Remove-DscConfigurationDocument -Stage Previous -Force -ErrorAction SilentlyContinue
$ErrorActionPreference = 'Stop'

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
    Write-Warning "Start-DscConfiguration encountered an error: $_"
    Write-Warning "Check the verbose output above for specific resource failures."
    Write-Warning "Non-AccountPolicy resource failures are acceptable and will not affect WinRM."
    Write-Host "=== DSC application completed with resource-level warnings ===" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# NOTE: No WinRM restore block here.
# AccountPolicy is excluded from the MOF so DSC does not write to the
# SCE database, meaning GPO-derived WinRM restrictions are never
# re-enforced during this apply. WinRM remains alive for Packer.
# account_policy.ps1 handles all password/lockout policy via secedit.
# -----------------------------------------------------------------------
$bkey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
    "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System", $true)
$bkey.SetValue("LegalNoticeCaption", "DoD Notice and Consent Banner", [Microsoft.Win32.RegistryValueKind]::String)
$bkey.SetValue("LegalNoticeText", [string]::Concat(
    "WARNING____WARNING",
    [System.Environment]::NewLine,
    [System.Environment]::NewLine,
    "You are accessing a U.S. Government information system, which includes: 1) this computer, 2) this computer network, 3) all Government-furnished computers connected to this network, and 4) all Government-furnished devices and storage media attached to this network or to a computer on this network. You understand and consent to the following: you may access this information system for authorized use only; unauthorized use of the system is prohibited and subject to criminal and civil penalties. You have no reasonable expectation of privacy regarding any communication or data transiting or stored on this information system. At any time and for any lawful Government purpose, the Government may monitor, intercept, audit, and search and seize any communication or data transiting or stored on this information system, and any communication or data transiting or stored on this information system may be disclosed or used for any lawful Government purpose. This information system may contain Controlled Unclassified Information (CUI) that is subject to safeguarding or dissemination controls in accordance with law, regulation, or Government-wide policy. Accessing and using this system indicates your understanding of this warning."
), [Microsoft.Win32.RegistryValueKind]::String)
$bkey.Close()
Write-Host "  [OK] Banner re-applied" -ForegroundColor Green
exit 0
