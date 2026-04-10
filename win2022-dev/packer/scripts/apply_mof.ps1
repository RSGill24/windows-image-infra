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

    FIX: Added $ErrorActionPreference = 'Continue' before banner re-apply
         block so that any DSC error does not abort banner code execution.

    FIX: Banner re-applied after DSC using StringBuilder + [char]13/10
         because [System.Environment]::NewLine becomes null in Packer
         child process uploads.

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

$ErrorActionPreference = 'Continue'
Stop-DscConfiguration -Force -ErrorAction SilentlyContinue
Remove-DscConfigurationDocument -Stage Current  -Force -ErrorAction SilentlyContinue
Remove-DscConfigurationDocument -Stage Pending  -Force -ErrorAction SilentlyContinue
Remove-DscConfigurationDocument -Stage Previous -Force -ErrorAction SilentlyContinue
$ErrorActionPreference = 'Stop'

Write-Host "LCM cache cleared." -ForegroundColor Green

# -----------------------------------------------------------------------
# Apply DSC configuration
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
# Banner re-apply — DSC/secedit overwrite karta hai LegalNoticeText
# $ErrorActionPreference = 'Continue' zaroori hai taaki koi bhi
# DSC error banner code ko abort na kare
# StringBuilder + [char]13/10 use karo — Packer mein [System.Environment]
# ::NewLine null ban jaata hai
# -----------------------------------------------------------------------
$ErrorActionPreference = 'Continue'

Write-Host "Re-applying DoD banner after DSC..." -ForegroundColor Yellow

try {
    $bkey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
        "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System", $true)

    $bkey.SetValue("LegalNoticeCaption", "DoD Notice and Consent Banner", [Microsoft.Win32.RegistryValueKind]::String)

    $warningLine = "WARNING____WARNING"
    $bodyText    = "You are accessing a U.S. Government information system, which includes: 1) this computer, 2) this computer network, 3) all Government-furnished computers connected to this network, and 4) all Government-furnished devices and storage media attached to this network or to a computer on this network. You understand and consent to the following: you may access this information system for authorized use only; unauthorized use of the system is prohibited and subject to criminal and civil penalties. You have no reasonable expectation of privacy regarding any communication or data transiting or stored on this information system. At any time and for any lawful Government purpose, the Government may monitor, intercept, audit, and search and seize any communication or data transiting or stored on this information system, and any communication or data transiting or stored on this information system may be disclosed or used for any lawful Government purpose. This information system may contain Controlled Unclassified Information (CUI) that is subject to safeguarding or dissemination controls in accordance with law, regulation, or Government-wide policy. Accessing and using this system indicates your understanding of this warning."

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append($warningLine)
    [void]$sb.Append([char]13)
    [void]$sb.Append([char]10)
    [void]$sb.Append([char]13)
    [void]$sb.Append([char]10)
    [void]$sb.Append($bodyText)
    $bannerText = $sb.ToString()

    $bkey.SetValue("LegalNoticeText", $bannerText, [Microsoft.Win32.RegistryValueKind]::String)
    $bkey.Close()

    Write-Host "  [OK] Banner re-applied" -ForegroundColor Green
} catch {
    Write-Warning "  Banner re-apply failed: $_"
}

exit 0
